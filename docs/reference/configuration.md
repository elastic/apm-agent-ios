---
mapped_pages:
  - https://www.elastic.co/guide/en/apm/agent/swift/current/configuration.html
---

# Configuration [configuration]

Configure the agent with `AgentConfigBuilder` passing the `AgentConfiguration` to the `start` function.

```swift
let config = AgentConfigBuilder()
                .withServerUrl(URL(string: "http://localhost:8200"))
                .withSecretToken("<Token>")
                .build()

ElasticApmAgent.start(with:config)
```


### Configuration options [configuration-options]

The `AgentConfigBuilder` can be configured with the following functions:

#### `withServerUrl` [withServerUrl] **Deprecated**

* **Type:** URL
* **Default:** nil

The URL host endpoint that handles both OTLP data export as well as Elastic Central Config.
This configuration option is deprecated. Use `withExportUrl` instead.

#### `withExportUrl` [withExportUrl]
* **Type:** URL
* **Default:** `http://127.0.0.1:8200`

The host enpoint handling OTLP exports. This configuration will override `withServerUrl` when set.

#### `withManagementUrl` [withManagementUrl]
* **Type:** URL
* **Default:** ${exportUrl}/config/v1/agents

The URL endpoint that handles Elastic Central Config.
It must be set with the correct path, e.g.: `/config/v1/agents`
For backwards compatibility purposes, if this config is unset the agent will use the value set by `withExportUrl` as the host.

This config is intended to be used in conjunction with `withExportUrl`.

#### `withRemoteManagement` [withRemoteManagement]
* **Type:** Bool
* **Default:** `true`

Controls whether the agent attempts to contact Elastic Central Config for runtime configuration updates.

#### `withSecretToken` [secretToken]

* **Type:** String
* **Default:** nil
* **Env:** `OTEL_EXPORTER_OTLP_HEADERS`

Sets the secret token for connecting to an authenticated APM Server. If using the env-var, the whole header map must be defined per [OpenTelemetry Protocol Exporter Config](https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/protocol/exporter.md) (e.g.: `OTEL_EXPORTER_OTLP_HEADERS="Authorization=bearer <secret token>"`)

This setting is mutually exclusive with `withApiKey`


#### `withApiKey` [withApiKey]

* **Type:** String
* **Default:** nil
* **Env:** `OTEL_EXPORTER_OTLP_HEADERS`

Sets the API Token for connecting to an authenticated APM Server. If using the env-var, the whole header map must be defined per [OpenTelemetry Protocol Exporter Config](https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/protocol/exporter.md) (e.g.: `OTEL_EXPORTER_OTLP_HEADERS="Authorization=ApiKey <key>"`)

This setting is mutually exclusive with `withSecretToken`


##### `disableAgent() -> Self` [disableAgent]

Disables the Elastic agent. This is useful for disabling the agent during development without having to remove the Elastic agent completely. A log will report `"Elastic APM Agent has been disabled."`


#### `addSpanFilter` [addSpanFilter]

* **Type:** @escaping (ReadableSpan) → Bool
* **Default:** nil

Adds an anonymous function that will be executed on each span in the span processor to decide if that span should be sent to the back end.


#### `addMetricFilter` [addMetricFilter]

* **Type:** @escaping (Metric) → Bool
* **Default:** nil

Adds an anonymous function that will be executed on each metric in the span processor to decide if that metric should be sent to the back end.


#### `addLogFilter` [addLogFilter]

* **Type:** @escaping (ReadableLogRecord) → Bool
* **Default:** nil

Adds an anonymous function that will be executed on each log in the span processor to decide if that log should be sent to the back end.


## Instrumentation configuration [instrumentationConfiguration]

The `ElasticApmAgent.start` provides an additional optional parameter for configuring instrumentation. In the below example, an instrumentation configuration is passed to `Agent.start` with default values. This is equivalent to calling `ElasticApmAgent.start` with no instrumentation configuration passed.

```swift
let config = ...

let instrumentationConfig = InstrumentationConfigBuilder().build()

ElasticApmAgent.start(with:config, instrumentationConfig)
```


### Instrumentation config options [instrumentationConfigOptions]

`InstrumentationConfigBuilder` can be configured with the following functions.


#### `withCrashReporting(_ enable: Bool) -> Self` [withCrashReporting]

* **Type:** Bool
* **Default:** `true`

This option can be used to enable/disable the crash reporting functionality of the agent.


#### `withURLSessionInstrumentation(_ enable: Bool) -> Self` [withURLSessionInstrumentation]

* **Type:** Bool
* **Default:** `true`

This option can be used to enable/disable the network tracing instrumentation.


#### `withViewControllerInstrumentation(_ enable: Bool) -> Self` [withViewControllerInstrumentation]

* **Type:** Bool
* **Default:** `true`

This option can be used to enable/disable the view controller tracing instrumentation.


#### `withAppMetricInstrumentation(_ enable: Bool) -> Self` [withAppMetricInstrumentation]

* **Type:** Bool
* **Default:** `true`

This option can be used to enable/disable [MetricKit](https://developer.apple.com/documentation/metrickit) instrumentation.


#### `withSystemMetrics(_ enable: Bool) -> Self` [withSystemMetrics]

* **Type:** Bool
* **Default:** `true`

This option can be used to enable/disable systems metrics instrumentation (CPU & memory usage).


#### `withLifecycleEvents(_ enable: Bool) -> Self` [withLifecycleEvents]

* **Type:** Bool
* **Default:** `true`

This option can be used to enable/disable lifecycle events.


#### `withPersistentStorageConfiguration(_ config: PersistencePerformancePreset) -> Self` [withPersistentStorageConfiguration]

* **Type:** `PersistencePerformancePreset`
* **Default:** `.lowRuntimeImpact`

This option can be used to configure the behavior of the [persistent stores](https://github.com/open-telemetry/opentelemetry-swift/tree/main/Sources/Exporters/Persistence) for traces, metrics, and logs.


## Resource attribute injection [resourceAttributeInjection]

In v0.5.0, the agent provides a means to set [resource attributes](https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/resource/sdk.md#specifying-resource-information-via-an-environment-variable) using the `OTEL_RESOURCE_ATTRIBUTES` env-var. This env-var also works through the application plist. Any resource attribute  can be overridden using this method, so care should be taken, as some attributes are critical to the functioning of the kibana UI.


### `deployment.environment` [deplyoment-environment]

Deployment environment is set to `default`. This can be overridden using the `OTEL_RESOURCE_ATTRIBUTES` set in your deployment’s plist. Use the field key as `OTEL_RESOURCE_ATTRIBUTES` and the value as `deployment.environment=staging`


### Dynamic configuration ![dynamic config](images/dynamic-config.svg "") [dynamic-configuration]

Dynamic configurations are available through the kibana UI and are read by the agent remotely to apply configuration on all active agents deployed in the field. More info on dynamic configurations can be found in  [agent configurations](docs-content://solutions/observability/apps/apm-agent-central-configuration.md).


#### Recording [recording]

A boolean specifying if the agent should be recording or not. When recording, the agent instruments incoming HTTP requests, tracks errors and collects and sends metrics. When not recording, the agent works as a noop, not collecting data and not communicating with the APM sever, except for polling the central configuration endpoint. As this is a reversible switch, agent threads are not being killed when inactivated, but they will be mostly idle in this state, so the overhead should be negligible.

You can set this setting to dynamically disable Elastic APM at runtime

![dynamic config](images/dynamic-config.svg "")

| Default | Type | Dynamic |
| --- | --- | --- |
| `true` | Boolean | true |


#### Session sample rate [session-sample-rate]

A double specifying the likelihood all data generated during a session should be recorded on a specific device. Value may range between 0 and 1. 1 meaning 100% likely, and 0 meaning 0% likely. Everytime a new session starts, this value will be checked against a random number between 0 and 1, and will sample all data recorded in that session of the random number is below the session sample rate set.

This session focused sampling technique is to preserve related data points, as opposed to sampling signal by signal, where valuable context can be lost.

You can set this value dynamically at runtime.

![dynamic config](images/dynamic-config.svg "")

| Default | Type | Dynamic |
| --- | --- | --- |
| `1.0` | Double | true |

