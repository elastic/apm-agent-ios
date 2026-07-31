---
navigation_title: Configuration
description: Comprehensive list of configuration parameters for the Elastic Distribution of OpenTelemetry iOS (EDOT iOS).
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

This page contains the configuration available for EDOT iOS, including values you set during initialization and values you can update remotely afterward.

Just getting started? Complete [Agent setup](getting-started.md#initialize) first.

## Initialization configuration [initialization-configuration]

Create an `AgentConfiguration` with `AgentConfigBuilder` and pass it to `ElasticApmAgent.start`:

```swift
import ElasticApm
import Foundation

let configuration = AgentConfigBuilder()
  .withExportUrl(URL(string: "https://your-otlp-endpoint")!)
  .withApiKey("your-api-key")
  .useConnectionType(.http)
  .build()

ElasticApmAgent.start(with: configuration)
```

### Export connectivity [export-connectivity]

Configure where EDOT iOS exports telemetry and which OTLP transport it uses:

```swift
let configuration = AgentConfigBuilder()
  .withExportUrl(URL(string: "https://collector.example.com:4318")!) // <1>
  .useConnectionType(.http) // <2>
  .build()
```

1. The base endpoint that receives OTLP data.
2. The OTLP transport. Use `.http` for OTLP/HTTP or `.grpc` for OTLP/gRPC.

#### `withExportUrl(_:)` [withExportUrl]

| Type | Required |
| --- | --- |
| `URL` | Yes |

Sets the OTLP endpoint provided by an Elastic Agent or EDOT Collector gateway.

When the connection type is `.http`, EDOT iOS appends `/v1/traces`, `/v1/metrics`, or `/v1/logs` to the configured path for each signal. When the connection type is `.grpc`, all signals use the configured gRPC endpoint.

#### `useConnectionType(_:)` [useConnectionType]

| Type | Default |
| --- | --- |
| `AgentConnectionType` | `.grpc` |

Selects the OTLP transport:

- `.grpc` uses the OTLP/gRPC exporters.
- `.http` uses the OTLP/HTTP exporters.

Make sure the endpoint supports the selected transport. EDOT Collector commonly listens on port `4317` for gRPC and `4318` for HTTP.

#### `withServerUrl(_:)` [withServerUrl]

```{applies_to}
product:
  edot_ios: deprecated 2.0.0
```

| Type | Default |
| --- | --- |
| `URL` | Not set |

Sets a single URL host endpoint that handles both OTLP data export and central configuration. This option is deprecated: use [`withExportUrl(_:)`](#withExportUrl) for OTLP data export and [`withManagementUrl(_:)`](#withManagementUrl) for central configuration instead.

### Authentication [authentication]

EDOT iOS supports APM agent keys and secret tokens. Configure only one authentication method. If you call both methods, the last value set on the builder is used.

#### `withApiKey(_:)` [withApiKey]

| Type | Default |
| --- | --- |
| `String` | No authentication |

Sets an APM agent key and sends it in the `Authorization` header using the `ApiKey` scheme:

```swift
let configuration = AgentConfigBuilder()
  .withExportUrl(URL(string: "https://your-otlp-endpoint")!)
  .withApiKey("your-api-key")
  .build()
```

Create an [APM agent key for EDOT SDKs](docs-content://solutions/observability/apm/opentelemetry/create-apm-agent-key-for-edot-sdks.md) to use least-privilege credentials.

#### `withSecretToken(_:)` [secretToken]

| Type | Default |
| --- | --- |
| `String` | No authentication |

Sets an APM secret token and sends it in the `Authorization` header using the `Bearer` scheme:

```swift
let configuration = AgentConfigBuilder()
  .withExportUrl(URL(string: "https://your-otlp-endpoint")!)
  .withSecretToken("your-secret-token")
  .build()
```

Refer to [APM secret tokens](docs-content://solutions/observability/apm/secret-token.md) for deployment requirements.

### Remote management connectivity [remote-management-connectivity]

EDOT iOS retrieves central configuration from an EDOT Collector through an OpAMP endpoint.

#### `withManagementUrl(_:)` [withManagementUrl]

| Type | Default |
| --- | --- |
| `URL` | Not set |

Sets the OpAMP endpoint used for central configuration. Set it explicitly and enable OpAMP:

```swift
let configuration = AgentConfigBuilder()
  .withExportUrl(URL(string: "https://your-otlp-endpoint")!)
  .withManagementUrl(
    URL(string: "https://your-edot-collector:4320/v1/opamp")!
  )
  .useOpAMP()
  .build()
```

#### `useOpAMP()` [useOpAMP]

| Type | Default |
| --- | --- |
| Method call | Disabled |

Enables OpAMP-based central configuration. When enabled, EDOT iOS treats `withManagementUrl(_:)` as an OpAMP endpoint.

Refer to [Central configuration](#central-configuration) for the complete setup.

#### `withRemoteManagement(_:)` [withRemoteManagement]

| Type | Default |
| --- | --- |
| `Bool` | `true` |

Controls whether EDOT iOS contacts central configuration for runtime configuration updates. Set it to `false` to turn off remote management entirely.

### Session behavior [session-behavior]

EDOT iOS makes a span sampling decision when a new app session begins.

#### `withSessionSampleRate(_:)` [withSessionSampleRate]

| Type | Default | Range |
| --- | --- | --- |
| `Double` | `1.0` | `0.0` through `1.0` |

Sets the probability that spans from a new session are sampled. A value of `1.0` samples every session, `0.0` samples none. Values outside this range are clamped to the closest valid value.

```swift
let configuration = AgentConfigBuilder()
  .withSessionSampleRate(0.5)
  .build()
```

The sampling decision is reused for the session so related spans are kept together. A session expires after 30 minutes of inactivity.

### Filter signals [filter-signals]

Filters run before spans or log records are exported. Return `true` to keep a signal or `false` to drop it.

#### `addSpanFilter(_:)` [addSpanFilter]

Adds a span filter:

```swift
let configuration = AgentConfigBuilder()
  .addSpanFilter { span in
    span.name != "health-check"
  }
  .build()
```

You can add multiple filters. A span is dropped when any filter returns `false`.

#### `addLogFilter(_:)` [addLogFilter]

Adds a log record filter:

```swift
let configuration = AgentConfigBuilder()
  .addLogFilter { logRecord in
    logRecord.severity != .trace
  }
  .build()
```

You can add multiple filters. A log record is dropped when any filter returns `false`.

### Intercept attributes [intercept-attributes]

Attribute interceptors run on every span or log record and can read, add, replace, or remove attributes.

#### `addSpanAttributeInterceptor(_:)` [addSpanAttributeInterceptor]

Adds an interceptor for span attributes:

```swift
import ElasticApm
import OpenTelemetryApi

let interceptor = ClosureInterceptor<[String: AttributeValue]> { attributes in
  var updatedAttributes = attributes
  updatedAttributes["app.release_channel"] = .string("beta")
  return updatedAttributes
}

let configuration = AgentConfigBuilder()
  .addSpanAttributeInterceptor(interceptor)
  .build()
```

#### `addLogRecordAttributeInterceptor(_:)` [addLogRecordAttributeInterceptor]

Adds an interceptor for log record attributes:

```swift
import ElasticApm
import OpenTelemetryApi

let interceptor = ClosureInterceptor<[String: AttributeValue]> { attributes in
  var updatedAttributes = attributes
  updatedAttributes["app.release_channel"] = .string("beta")
  return updatedAttributes
}

let configuration = AgentConfigBuilder()
  .addLogRecordAttributeInterceptor(interceptor)
  .build()
```

You can add multiple interceptors. EDOT iOS runs them in the order they were added.

### Disable the SDK [disable-sdk]

#### `disableAgent()` [disableAgent]

Builds a configuration that prevents EDOT iOS from starting:

```swift
let configuration = AgentConfigBuilder()
  .disableAgent()
  .build()

ElasticApmAgent.start(with: configuration)
```

Use this when you need to keep the dependency in your app but disable it for a build or environment.

## Automatic instrumentation configuration [instrumentationConfiguration]

Create an `InstrumentationConfiguration` with `InstrumentationConfigBuilder` and pass it as the second argument to `ElasticApmAgent.start`:

```swift
let agentConfiguration = AgentConfigBuilder()
  .withExportUrl(URL(string: "https://your-otlp-endpoint")!)
  .build()

let instrumentationConfiguration = InstrumentationConfigBuilder()
  .withCrashReporting(false)
  .withSystemMetrics(false)
  .build()

ElasticApmAgent.start(
  with: agentConfiguration,
  instrumentationConfiguration
)
```

### Instrumentation options [instrumentationConfigOptions]

#### `withCrashReporting(_:)` [withCrashReporting]

| Type | Default |
| --- | --- |
| `Bool` | `true` |

Turns [crash reporting](automatic-instrumentation.md#crash-reporting) on or off.

#### `withURLSessionInstrumentation(_:)` [withURLSessionInstrumentation]

| Type | Default |
| --- | --- |
| `Bool` | `true` |

Turns [URLSession instrumentation](automatic-instrumentation.md#urlsession-instrumentation) on or off.

#### `withViewControllerInstrumentation(_:)` [withViewControllerInstrumentation]

| Type | Default |
| --- | --- |
| `Bool` | `true` |

Turns [SwiftUI and UIViewController instrumentation](automatic-instrumentation.md#view-instrumentation) on or off.

#### `withAppMetricInstrumentation(_:)` [withAppMetricInstrumentation]

```{applies_to}
product:
  edot_ios: deprecated 2.0.1
```

| Type | Default |
| --- | --- |
| `Bool` | `true` |

Previously turned [MetricKit](https://developer.apple.com/documentation/metrickit) instrumentation on or off. This option is deprecated and has no effect.

#### `withSystemMetrics(_:)` [withSystemMetrics]

| Type | Default |
| --- | --- |
| `Bool` | `true` |

Turns [CPU and memory metrics](automatic-instrumentation.md#system-metrics) on or off.

#### `withLifecycleEvents(_:)` [withLifecycleEvents]

| Type | Default |
| --- | --- |
| `Bool` | `true` |

Turns [application lifecycle events](automatic-instrumentation.md#app-lifecycle-events) on or off.

#### `withPersistentStorageConfiguration(_:)` [withPersistentStorageConfiguration]

| Type | Default |
| --- | --- |
| `PersistencePerformancePreset` | `.default`, equivalent to `.lowRuntimeImpact` |

Configures [persistent storage](https://github.com/open-telemetry/opentelemetry-swift/tree/main/Sources/Exporters/Persistence) for traces, metrics, and logs:

```swift
let instrumentationConfiguration = InstrumentationConfigBuilder()
  .withPersistentStorageConfiguration(.instantDataDelivery)
  .build()
```

The available upstream presets are:

- `.lowRuntimeImpact`, the default, which favors lower runtime overhead.
- `.instantDataDelivery`, which checks for exportable data more often.

## Resource attributes [resourceAttributeInjection]

EDOT iOS detects app, device, operating system, process, and telemetry SDK resource attributes. It also reads custom resource attributes from `OTEL_RESOURCE_ATTRIBUTES`.

You can provide this value through the process environment or your app's `Info.plist`:

```xml
<key>OTEL_RESOURCE_ATTRIBUTES</key>
<string>deployment.environment.name=staging,service.name=my-ios-app</string>
```

The format is a comma-separated list of `key=value` pairs. Values from the process environment override matching values from `Info.plist`.

Resource attributes affect how {{kib}} identifies and groups telemetry. Take care when overriding attributes such as `service.name`, `service.version`, and `deployment.environment.name`.

### Deployment environment [deployment-environment]

EDOT iOS sets `deployment.environment.name` to `default`. Override it with `OTEL_RESOURCE_ATTRIBUTES`:

```text
deployment.environment.name=staging
```

## Dynamic configuration [dynamic-configuration]

Dynamic settings can change after EDOT iOS starts. The SDK retrieves them through [Central configuration](#central-configuration).

### Recording [recording]

Controls whether EDOT iOS processes and exports log records. Central configuration polling remains active when recording is disabled.

| Default | Type | Dynamic |
| --- | --- | --- |
| `true` | Boolean | Yes |

### Session sample rate [session-sample-rate]

Controls the probability that spans from a new session are sampled. The value can range from `0.0` to `1.0`.

The setting is evaluated when a new session begins. This keeps related spans together instead of making a separate decision for every span.

| Default | Type | Dynamic |
| --- | --- | --- |
| `1.0` | Double | Yes |

## Central configuration [central-configuration]

```{applies_to}
product:
  edot_ios: preview 1.4.0
```

EDOT iOS receives central configuration from an EDOT Collector through OpAMP.

To use an EDOT Collector OpAMP endpoint:

```swift
let configuration = AgentConfigBuilder()
  .withExportUrl(URL(string: "https://your-otlp-endpoint")!)
  .withManagementUrl(
    URL(string: "https://your-edot-collector:4320/v1/opamp")!
  )
  .withApiKey("your-api-key")
  .useOpAMP()
  .build()

ElasticApmAgent.start(with: configuration)
```

Refer to [Central configuration for EDOT SDKs](opentelemetry://reference/central-configuration.md) for EDOT Collector and {{kib}} setup.

### Available settings [central-configuration-settings]

| Setting | Description | Type |
| --- | --- | --- |
| Recording | Whether EDOT iOS processes and exports log records. | Dynamic |
| Session sample rate | The probability that spans from a new session are sampled. | Dynamic |
