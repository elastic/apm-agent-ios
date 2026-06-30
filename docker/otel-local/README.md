# Local Elastic Stack and EDOT Collector

This directory runs Elasticsearch, Kibana, and the Elastic Distribution of OpenTelemetry (EDOT) Collector for local development of the iOS agent. Traces, logs, and periodic metrics work with the stock [gateway-style](https://www.elastic.co/docs/reference/edot-collector/config/default-config-standalone) pipeline. **MetricKit application metrics** (`application.launch.time`, `application.responsiveness.hangtime`, `application.exits`) need extra collector processors and routing so documents land in the APM application-metrics data streams that Kibana expects.

The reference configuration is [`otel-collector-config.yml`](otel-collector-config.yml).

## Quick start

```bash
cd docker/otel-local
cp env.example .env
docker compose up -d
```

Point the app at your host IP (not `localhost` from a physical device):

| Endpoint        | URL / port              |
|-----------------|-------------------------|
| OTLP gRPC       | `<host-ip>:4317`        |
| OTLP HTTP       | `http://<host-ip>:4318` |
| Elasticsearch   | `http://<host-ip>:9200` |
| Kibana          | `http://<host-ip>:5601` |

Validate the collector config after edits:

```bash
docker exec edot-local-collector elastic-agent otel validate \
  --config=file:/etc/otelcol/otel-collector-config.yml
```

Restart only the collector when you change the YAML:

```bash
docker compose restart edot-collector
```

Ensure Elasticsearch is healthy before restarting the collector. If ES is down during a metric export, the collector may log `Exporting failed. Dropping data` and those MetricKit payloads are lost.

## Why MetricKit metrics need a different pipeline

The iOS agent exports MetricKit data as OTLP metrics from the `ApplicationMetrics` instrumentation scope. That path differs from trace-derived APM metrics (produced by the `elasticapm` connector) in several ways:

| Aspect | Trace-derived metrics | MetricKit (`ApplicationMetrics`) |
|--------|----------------------|----------------------------------|
| Trigger | Continuous / interval from traces | On demand when Apple delivers `MXMetricPayload` |
| Histogram temporality | Already compatible with export | Agent exports **delta** histograms |
| Elasticsearch mapping | OTel-native (`metrics-*.otel`) | Needs **ECS** mapping for `application.*` fields |
| Kibana data stream | `metrics-transaction.*.otel`, etc. | `metrics-apm.app.<service>-*` |
| `@timestamp` | Near export time | **MetricKit reporting window end** (can be hours old) |

A minimal gateway config (OTLP → `batch` → `elasticsearch/otel`) is enough for traces but will not surface `application.launch.time` in Kibana APM. You will often see metrics in collector **debug** logs while Elasticsearch has no usable documents.

## Required collector configuration

The `metrics` pipeline in `otel-collector-config.yml` adds three pieces on top of the default gateway setup.

### 1. `cumulativetodelta` processor

The Elasticsearch OTel exporter accepts **delta** histograms only. If a metric arrives as cumulative temporality, the exporter drops it:

```text
dropping cumulative temporality histogram "application.launch.time"
```

The iOS agent already reports delta histograms for MetricKit, but this processor still belongs in the pipeline so other OTLP clients or SDK versions do not break export. Use `initial_value: keep` so the first observation after a collector restart is not discarded (gateway-friendly default is `drop`).

```yaml
processors:
  cumulativetodelta:
    initial_value: keep
```

### 2. `elasticapm` processor

Enriches OTLP metrics with APM-oriented resource attributes (for example `metricset.name: app`) and prepares them for Elastic Observability. Enable service name in the data stream dataset when you route app metrics explicitly:

```yaml
processors:
  elasticapm:
    service_name_in_datastream_dataset: true
```

This processor must run **before** the transform that sets routing attributes.

### 3. `transform/apm-app-ecs` processor (EDOT 9.4+)

In EDOT Collector 9.4, the `mapping.mode` field under `elasticsearch/otel` in YAML is **deprecated and ignored**. Mapping mode is chosen per signal via the scope attribute `elastic.mapping.mode` or client metadata `X-Elastic-Mapping-Mode`.

For MetricKit metrics, set **ECS** mapping on the `ApplicationMetrics` scope and route to the application-metrics dataset:

```yaml
processors:
  transform/apm-app-ecs:
    error_mode: ignore
    metric_statements:
      - context: scope
        conditions:
          - scope.name == "ApplicationMetrics"
        statements:
          - set(scope.attributes["elastic.mapping.mode"], "ecs")
          - set(resource.attributes["data_stream.dataset"], Concat(["apm.app.", resource.attributes["service.name"]], ""))
```

Elasticsearch sanitizes `service.name` for index naming (for example `opbeans-swift` → `apm.app.opbeans_swift`).

### Complete `metrics` pipeline

Processor order matters:

```yaml
service:
  pipelines:
    metrics:
      receivers: [otlp]
      processors: [cumulativetodelta, elasticapm, transform/apm-app-ecs, batch/metrics]
      exporters: [elasticsearch/otel, debug]
```

Trace-derived metrics continue to use the separate `metrics/aggregated-otel-metrics` pipeline from the `elasticapm` connector; do not remove that pipeline.

```mermaid
flowchart LR
  app[iOS agent MetricKit]
  otlp[OTLP receiver]
  ctd[cumulativetodelta]
  apm[elasticapm processor]
  tfm[transform apm-app-ecs]
  batch[batch/metrics]
  es[elasticsearch/otel]
  ds[(metrics-apm.app.service)]

  app --> otlp --> ctd --> apm --> tfm --> batch --> es --> ds
```

## Where data appears in Elasticsearch

After a successful export, documents are in data streams such as:

```text
metrics-apm.app.<sanitized-service-name>-default
```

Example for `service.name: opbeans-swift`:

```text
metrics-apm.app.opbeans_swift-default
```

Relevant fields (ECS shape):

| Field | Description |
|-------|-------------|
| `application.launch.time` | Histogram buckets for launch duration (`ms`) |
| `application.responsiveness.hangtime` | Hang-time histogram |
| `application.exits` | Exit counters (iOS 14+) |
| `type` | Launch subtype: `first draw`, `optimized first draw`, `resume` |
| `service.name` | From agent resource attributes |
| `@timestamp` | End of the MetricKit reporting window (`MXMetricPayload.timeStampEnd`) |

Do **not** search only `metrics-generic.otel-*` or field `metrics.application.launch.time` unless you intentionally use OTel-native mapping without the ECS transform.

## Verifying in Kibana or Dev Tools

1. Trigger a **new** MetricKit delivery (kill app, cold launch, background; Apple does not resend old daily payloads).
2. In Kibana Discover, use a data view matching **`metrics-apm.app.*`**.
3. Set the time range to **Last 7 days** (or wider). MetricKit timestamps are often behind wall clock.
4. Filter on `service.name` and confirm `application.launch.time` exists.

Dev Tools example:

```json
GET metrics-apm.app.*/_search
{
  "size": 10,
  "query": {
    "bool": {
      "must": [
        { "term": { "service.name": "opbeans-swift" } },
        { "exists": { "field": "application.launch.time" } }
      ]
    }
  },
  "sort": [{ "@timestamp": "desc" }]
}
```

Optional smoke test from the host (does not replace a real device export):

```bash
python3 scripts/send_test_histogram.py
```

## Agent-side requirements

Collector configuration alone is not sufficient. The iOS agent must:

- Export MetricKit metrics on the **`ApplicationMetrics`** instrumentation scope (default).
- Use the same **`service.name`** as traces (for example via `OTEL_RESOURCE_ATTRIBUTES`).
- Send **delta** histogram temporality for MetricKit (handled by `MetricKitTriggeredMetricReader`).
- Reach the collector at a reachable host IP on port **4317** (gRPC) or **4318** (HTTP).

Recent agent builds strip histogram exemplars before MetricKit export because exemplars without trace IDs can interfere with Elasticsearch indexing.

Enable MetricKit in agent configuration (`enableMetricKit` / instrumentation config). See [MetricKit instrumentation](../../docs/reference/edot-ios/instrumentation.md#metrickit-instrumentation).

## Troubleshooting

| Symptom | Likely cause | What to check |
|---------|----------------|---------------|
| Metric names in collector logs, nothing in Kibana | Wrong index pattern or time range | `metrics-apm.app.*`, widen time picker |
| `dropping cumulative temporality histogram` in collector logs | Missing or mis-ordered `cumulativetodelta` | Add processor before `elasticsearch/otel` |
| Documents in `metrics-generic.otel` only | ECS transform missing or not applied to `ApplicationMetrics` | `transform/apm-app-ecs` and scope name |
| `Exporting failed. Dropping data` | Elasticsearch down during export | Start ES first, restart collector, re-export from app |
| Traces work, metrics never arrive | App not reaching collector on metrics path | Same host:port as traces; check gRPC vs HTTP |
| Old launch data missing after stack restart | Payload dropped during outage | New MetricKit delivery required |

Collector debug exporter shows received OTLP; it does **not** prove Elasticsearch indexed documents. Confirm with Dev Tools or Discover on `metrics-apm.app.*`.

## References

- [EDOT Collector gateway (standalone)](https://www.elastic.co/docs/reference/edot-collector/config/default-config-standalone)
- [Elasticsearch exporter (mapping modes)](https://www.elastic.co/docs/reference/edot-collector/components/elasticsearchexporter)
- [Elastic APM metrics data streams](https://www.elastic.co/docs/solutions/observability/apm/metrics)
- [Mobile application metrics spec](https://github.com/elastic/apm/blob/main/specs/agents/mobile/metrics.md#application-metrics)
- In-repo config: [`otel-collector-config.yml`](otel-collector-config.yml)
