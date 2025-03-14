---
mapped_pages:
  - https://www.elastic.co/guide/en/apm/agent/swift/current/intro.html
  - https://www.elastic.co/guide/en/apm/agent/swift/current/index.html
---

# APM iOS agent [intro]

The Elastic APM iOS Agent measures the performance of your mobile applications in real-time.

::::{note}
The Elastic APM iOS Agent is not compatible with [{{serverless-full}}](docs-content://deploy-manage/deploy/elastic-cloud/serverless.md).

::::



## How does the agent work? [how-it-works]

The Elastic APM iOS Agent uses the [OpenTelemetry-Swift SDK](https://github.com/open-telemetry/opentelemetry-swift). The agent automatically traces URLSessions and provides distributed traces annotated with device information along with your back-end services instrumented with Open-Telemetry.

The agent also captures any custom open-telemetry traces or measurements created using the OpenTelemetry-Swift API.


## How to add instrumentation [manual-instrumentation]

This agent will configure the OpenTelementry-Swift `TracerProvider` and `MetricProvider`, and set them as the global OpenTelemetry providers. They can be accessed through the OpenTelemetry SDK as follows:

```swift
let tracerProvider = OpenTelemetry.instance.tracerProvider
let meterProvider = OpenTelemetry.instance.meterProvider
```

These objects can be used to acquire new tracers and meters that will send their captured data to the Elastic APM Server. More details on how to use OpenTelemetry to instrument your app can be found in the [OpenTelemetry.io Swift manual instrumentation docs](https://opentelemetry.io/docs/instrumentation/swift/manual).

Examples can be found in [opentelemetry-swift/examples](https://github.com/open-telemetry/opentelemetry-swift/tree/main/Examples).


## Additional components [additional-components]

APM Agents work in conjunction with the [APM Server](docs-content://solutions/observability/apps/application-performance-monitoring-apm.md), [{{es}}](docs-content://get-started/index.md), and [{{kib}}](docs-content://get-started/the-stack.md). The [APM Guide](docs-content://solutions/observability/apps/application-performance-monitoring-apm.md) provides details on how these components work together, and provides a matrix outlining [Agent and Server compatibility](docs-content://solutions/observability/apps/apm-agent-compatibility.md).


## Open Telemetry Components [_open_telemetry_components]

The iOS Agent utilizes several OpenTelemetry-Swift libraries to provide automatic instrumentation of your applications and services. Details about these instrumentation libraries can be found in the official [opentelementry.io Swift Libraries documentation](https://opentelemetry.io/docs/instrumentation/swift/libraries/).

For network instrumentation, the agent uses `NSURLSessionInstrumentation`. This provides network instrumentation in the form of spans and enables distributed tracing for all instrumented downstream services.

Detailed information on the device, operating system, and application is provided by `SDKResourceExtension`. More information on which data points are captured can be found in the  [opentelementry.io SDKResourceExtension documentation](https://opentelemetry.io/docs/instrumentation/swift/manual/#SDKResourceExtension).

Elastic maps OpenTelemetry attributes to Elastic-specific fields. Details of these mappings can be found in the [Elastic Mobile Agent Spec](https://github.com/elastic/apm/tree/main/specs/agents/mobile).

