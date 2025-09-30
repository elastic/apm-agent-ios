---
navigation_title: Configuration
description: Configure the Elastic Distribution of OpenTelemetry iOS (EDOT iOS) to send data to Elastic.
applies_to:
  stack:
  serverless:
    observability:
  product:
    edot_ios: ga
products:
  - id: cloud-serverless
  - id: observability
  - id: edot-sdk
mapped_pages:
  - https://www.elastic.co/guide/en/apm/agent/swift/current/configuration.html
---

# Configure the EDOT iOS SDK [configuration]

Configure the SDK with `AgentConfigBuilder` passing the `AgentConfiguration` to the `start` function.

```swift
let config = AgentConfigBuilder()
                .withServerUrl(URL(string: "http://localhost:8200"))
                .withSecretToken("<Token>")
                .build()

ElasticApmAgent.start(with:config)
```

## Configuration options [configuration-options]

You can configure the `AgentConfigBuilder` with the following functions.

#### `withServerUrl` [withServerUrl] **Deprecated**

* **Type:** URL
* **Default:** nil

The URL host endpoint that handles both OTLP data export as well as Elastic Central Configuration.
This configuration option is deprecated. Use `withExportUrl` instead.

### `withExportUrl` [withExportUrl]

* **Type:** URL
* **Default:** `http://127.0.0.1:8200`

The host endpoint handling OTLP exports. This configuration overrides `withServerUrl` when set.

### `withManagementUrl` [withManagementUrl]

* **Type:** URL
* **Default:** ${exportUrl}/config/v1/agents

The URL endpoint that handles Elastic Central Config. It must be set with the correct path, e.g.: `/config/v1/agents`. For backwards compatibility purposes, if this config is unset the SDK uses the value set by `withExportUrl` as the host. 

This config is intended to be used in conjunction with `withExportUrl`.

note: If `useOpAMP` is enabled, this URL should be set with your OpAMP endpoint, such as `http://localhost:4320/v1/opamp`. E.g.: 
```swift
let config = AgentConfigBuilder()
                .withServerUrl(URL(string: "http://localhost:8200")!)
                .withManagementUrl(URL(string:"http://localhost:4320/v1/opamp")!)
                .useOpAMP()
                .build()

ElasticApmAgent.start(with:config)
```

#### `withRemoteManagement` [withRemoteManagement]

* **Type:** Bool
* **Default:** `true`

Controls whether the SDK attempts to contact Elastic Central Config for runtime configuration updates.

#### `withSecretToken` [secretToken]

* **Type:** String
* **Default:** nil
* **Env:** `OTEL_EXPORTER_OTLP_HEADERS`

Sets the secret token for connecting to an authenticated APM Server. If using the env-var, the whole header map must be defined per [OpenTelemetry Protocol Exporter Config](https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/protocol/exporter.md) (e.g.: `OTEL_EXPORTER_OTLP_HEADERS="Authorization=bearer <secret token>"`)

This setting is mutually exclusive with `withApiKey`.

#### `withApiKey` [withApiKey]

* **Type:** String
* **Default:** nil
* **Env:** `OTEL_EXPORTER_OTLP_HEADERS`

Sets the API Token for connecting to an authenticated APM Server. If using the env-var, the whole header map must be defined per [OpenTelemetry Protocol Exporter Config](https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/protocol/exporter.md) (e.g.: `OTEL_EXPORTER_OTLP_HEADERS="Authorization=ApiKey <key>"`)

This setting is mutually exclusive with `withSecretToken`

#### `useConnectionType` [useConnectionType]

* **Type:** `AgentConnectionType`
* **Default:** `.grpc`

- Selects the transport used to export OTLP data to the collector. `.grpc` uses the gRPC OTLP exporter (default). `.http` uses the OTLP/HTTP exporters and will send traces, metrics, and logs to the HTTP endpoints (e.g. `/v1/traces`, `/v1/metrics`, `/v1/logs`). 

#### `useOpAMP` [useOpAMP]

* **Type:** Call to enable OpAMP
* **Default:** `false`

Enable OpAMP-based central management. When enabled, the agent will assume the url provided to `withManagementUrl` is an OpAMP endpoint. Use this when your central configuration is delivered via OpAMP. see [withManagementUrl](#withmanagementurl).
.

#### `disableAgent() -> Self` [disableAgent]

Turns off the Elastic SDK. This is useful for disabling the SDK during development without having to remove the Elastic SDK completely. A log reports `"Elastic APM Agent has been disabled."`

#### `addSpanFilter` [addSpanFilter]

* **Type:** `@escaping (ReadableSpan) → Bool`
* **Default:** nil

Adds an anonymous function that will be executed on each span in the span processor to decide if that span should be sent to the back end.

#### `addMetricFilter` [addMetricFilter]

* **Type:** `@escaping (Metric) → Bool`
* **Default:** nil

Adds an anonymous function that will be executed on each metric in the span processor to decide if that metric should be sent to the back end.

#### `addLogFilter` [addLogFilter]

* **Type:** `@escaping (ReadableLogRecord) → Bool`
* **Default:** nil

Adds an anonymous function that will be executed on each log in the span processor to decide if that log should be sent to the back end.

#### `addSpanAttributeInterceptor` [addSpanAttributeInterceptor]

* **Type:** `any Interceptor<[String:AttributeValue>]`
* **Default:** nil

You can provide interceptors for all spans attributes, which will be executed on every span created, where you can read/modify them if needed.

#### `addLogRecordAttributeInterceptor` [addLogRecordAttributeInterceptor]

* **Type:** `any Interceptor<[String:AttributeValue>]`
* **Default:** nil

You can provide interceptors for all LogRecord attributes, which will be executed on every span created, where you can read or modify them if needed.

## Instrumentation configuration [instrumentationConfiguration]

The `ElasticApmAgent.start` provides an additional optional parameter for configuring instrumentation. In the following example, an instrumentation configuration is passed to `Agent.start` with default values. This is equivalent to calling `ElasticApmAgent.start` with no instrumentation configuration passed.

```swift
let config = ...

let instrumentationConfig = InstrumentationConfigBuilder().build()

ElasticApmAgent.start(with:config, instrumentationConfig)
```

### Instrumentation config options [instrumentationConfigOptions]

You can configure the `InstrumentationConfigBuilder` with the following functions.


#### `withCrashReporting(_ enable: Bool) -> Self` [withCrashReporting]

* **Type:** Bool
* **Default:** `true`

Use this option to turn on or turn off the crash reporting functionality of the agent.

#### `withURLSessionInstrumentation(_ enable: Bool) -> Self` [withURLSessionInstrumentation]

* **Type:** Bool
* **Default:** `true`

Use this option to turn on or turn off the network tracing instrumentation.

#### `withViewControllerInstrumentation(_ enable: Bool) -> Self` [withViewControllerInstrumentation]

* **Type:** Bool
* **Default:** `true`

Use this option to turn on or turn off the view controller tracing instrumentation.

#### `withAppMetricInstrumentation(_ enable: Bool) -> Self` [withAppMetricInstrumentation]

* **Type:** Bool
* **Default:** `true`

Use this option to turn on or turn off [MetricKit](https://developer.apple.com/documentation/metrickit) instrumentation.

#### `withSystemMetrics(_ enable: Bool) -> Self` [withSystemMetrics]

* **Type:** Bool
* **Default:** `true`

Use this option to turn on or turn off systems metrics instrumentation (CPU & memory usage).

#### `withLifecycleEvents(_ enable: Bool) -> Self` [withLifecycleEvents]

* **Type:** Bool
* **Default:** `true`

Use this option to turn on or turn off lifecycle events.

#### `withPersistentStorageConfiguration(_ config: PersistencePerformancePreset) -> Self` [withPersistentStorageConfiguration]

* **Type:** `PersistencePerformancePreset`
* **Default:** `.lowRuntimeImpact`

Use this option to configure the behavior of the [persistent stores](https://github.com/open-telemetry/opentelemetry-swift/tree/main/Sources/Exporters/Persistence) for traces, metrics, and logs.

## Resource attribute injection [resourceAttributeInjection]

In v0.5.0, the SDK provides a means to set [resource attributes](https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/resource/sdk.md#specifying-resource-information-via-an-environment-variable) using the `OTEL_RESOURCE_ATTRIBUTES` env-var. This env-var also works through the application plist. Any resource attribute  can be overridden using this method, so care should be taken, as some attributes are critical to the functioning of the kibana UI.

#### `deployment.environment` [deployment-environment]

Deployment environment is set to `default`. This can be overridden using the `OTEL_RESOURCE_ATTRIBUTES` set in your deployment’s plist. Use the field key as `OTEL_RESOURCE_ATTRIBUTES` and the value as `deployment.environment=staging`

### Dynamic configuration ![dynamic config](images/dynamic-config.svg "") [dynamic-configuration]

Dynamic configurations are available through the {{kib}} UI and are read by the SDK remotely to apply configuration on all active agents deployed in the field. More info on dynamic configurations can be found in  [agent configurations](docs-content://solutions/observability/apps/apm-agent-central-configuration.md).

#### Recording [recording]

A boolean specifying if the SDK should be recording or not. When recording, the SDK instruments incoming HTTP requests, tracks errors and collects and sends metrics. When not recording, the SDK works as a noop, not collecting data and not communicating with the APM sever, except for polling the central configuration endpoint. As this is a reversible switch, SDK threads are not being killed when inactivated, but they will be mostly idle in this state, so the overhead should be negligible.

You can set this setting to dynamically disable Elastic APM at runtime.

![dynamic config](images/dynamic-config.svg "")

| Default | Type | Dynamic |
| --- | --- | --- |
| `true` | Boolean | true |


#### Session sample rate [session-sample-rate]

A double specifying the likelihood all data generated during a session should be recorded on a specific device. Value may range between 0 and 1. 1 meaning 100% likely, and 0 meaning 0% likely. Every time a new session starts, this value will be checked against a random number between 0 and 1, and will sample all data recorded in that session of the random number is below the session sample rate set.

This session focused sampling technique is to preserve related data points, as opposed to sampling signal by signal, where valuable context can be lost.

You can set this value dynamically at runtime.

![dynamic config](images/dynamic-config.svg "")

| Default | Type | Dynamic |
| --- | --- | --- |
| `1.0` | Double | true |

