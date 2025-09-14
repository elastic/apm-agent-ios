---
navigation_title: EDOT iOS
description: The Elastic Distribution of OpenTelemetry iOS (EDOT iOS) is an APM agent based on OpenTelemetry. It provides built-in tools and configurations to make the OpenTelemetry SDK work with Elastic using as little code as possible while fully leveraging the combined forces of Elasticsearch and Kibana for your iOS application.
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
  - https://www.elastic.co/guide/en/apm/agent/swift/current/intro.html
  - https://www.elastic.co/guide/en/apm/agent/swift/current/index.html
---

# Elastic Distribution of OpenTelemetry iOS [intro]

The Elastic Distribution of OpenTelemetry iOS (EDOT iOS) measures the performance of your mobile applications in real time.

## How does EDOT iOS work? [how-it-works]

The Elastic Distribution of OpenTelemetry iOS uses the [OpenTelemetry-Swift SDK](https://github.com/open-telemetry/opentelemetry-swift). The agent automatically traces URLSessions and provides distributed traces annotated with device information along with your back-end services instrumented with OpenTelemetry.

The SDK also captures any custom OpenTelemetry traces or measurements created using the OpenTelemetry-Swift API.

## How to add instrumentation [manual-instrumentation]

The SDK configures the OpenTelemetry-Swift `TracerProvider` and `MetricProvider`, and sets them as the global OpenTelemetry providers. They can be accessed through the OpenTelemetry SDK as follows:

```swift
let tracerProvider = OpenTelemetry.instance.tracerProvider
let meterProvider = OpenTelemetry.instance.meterProvider
```

You can use these objects to acquire new tracers and meters that send their captured data to the Elastic APM Server. For more details on how to use OpenTelemetry to instrument your app, refer to the [OpenTelemetry.io Swift manual instrumentation docs](https://opentelemetry.io/docs/instrumentation/swift/manual).

You can find examples in the [opentelemetry-swift/examples](https://github.com/open-telemetry/opentelemetry-swift/tree/main/Examples) repository.

## Additional components [additional-components]

EDOT SDKs work with the [APM Server](docs-content://solutions/observability/apps/application-performance-monitoring-apm.md), [{{es}}](docs-content://get-started/index.md), and [{{kib}}](docs-content://get-started/the-stack.md). The [APM Guide](docs-content://solutions/observability/apps/application-performance-monitoring-apm.md) provides details on how these components work together, and provides a matrix outlining [Agent and Server compatibility](docs-content://solutions/observability/apps/apm-agent-compatibility.md).

## OpenTelemetry Components [_open_telemetry_components]

The EDOT iOS SDK uses several OpenTelemetry-Swift libraries to provide automatic instrumentation of your applications and services. Details about these instrumentation libraries can be found in the official [opentelementry.io Swift Libraries documentation](https://opentelemetry.io/docs/instrumentation/swift/libraries/).

For network instrumentation, the agent uses `NSURLSessionInstrumentation`. This provides network instrumentation in the form of spans and enables distributed tracing for all instrumented downstream services.

Detailed information on the device, operating system, and application is provided by `SDKResourceExtension`. More information on which data points are captured can be found in the  [opentelementry.io SDKResourceExtension documentation](https://opentelemetry.io/docs/instrumentation/swift/manual/#SDKResourceExtension).

Elastic maps OpenTelemetry attributes to Elastic-specific fields. Details of these mappings can be found in the [Elastic Mobile Agent Spec](https://github.com/elastic/apm/tree/main/specs/agents/mobile).

