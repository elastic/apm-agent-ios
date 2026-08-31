---
navigation_title: Automatic instrumentation
description: Instrument iOS applications automatically using EDOT iOS.
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
  - https://www.elastic.co/guide/en/apm/agent/swift/current/Instrumentation.html
  - https://www.elastic.co/guide/en/apm/agent/swift/current/supported-technologies.html
---

# Automatic instrumentation for iOS applications with EDOT iOS [Instrumentation]

EDOT iOS can automatically generate telemetry on your behalf. This allows you to capture telemetry for supported Apple APIs and app lifecycle events without writing [manual instrumentation](manual-instrumentation.md).

## Installation [supported-instrumentations-installation]

Automatic instrumentations are bundled with EDOT iOS. After you add and [initialize the SDK](getting-started.md#initialize), supported instrumentations are enabled by default.

You do not need to add separate instrumentation packages.

## Configuration [automatic-instrumentation-configuration]

Use `InstrumentationConfigBuilder` to turn individual instrumentations on or off:

```swift
import ElasticApm
import Foundation

let agentConfiguration = AgentConfigBuilder()
  .withExportUrl(URL(string: "https://your-otlp-endpoint")!)
  .build()

let instrumentationConfiguration = InstrumentationConfigBuilder()
  .withCrashReporting(true)
  .withURLSessionInstrumentation(true)
  .withViewControllerInstrumentation(true)
  .withSystemMetrics(true)
  .withLifecycleEvents(true)
  .build()

ElasticApmAgent.start(
  with: agentConfiguration,
  instrumentationConfiguration
)
```

Refer to [Automatic instrumentation configuration](configuration.md#instrumentationconfiguration) for all options and defaults.

## Supported instrumentations [supported-instrumentations]

### URLSession instrumentation [urlsession-instrumentation]

URLSession instrumentation creates spans for requests made with `URLSession` and injects W3C trace context headers into outgoing requests. These headers connect the mobile span with spans created by an instrumented backend.

By default, EDOT iOS names spans using the HTTP method and destination host, for example `GET api.example.com`.

When a response has a status code from `400` through `599`, EDOT iOS adds an exception event with the status code and its localized description. Transport errors are also recorded as exception events.

URLSession spans include the current network connection type when it is available.

URLSession instrumentation is provided by OpenTelemetry-Swift. Refer to the [URLSession instrumentation source](https://github.com/open-telemetry/opentelemetry-swift/tree/main/Sources/Instrumentation/URLSession) for upstream implementation details.

### View instrumentation [view-instrumentation]

EDOT iOS creates spans that measure how long UIKit and SwiftUI-backed views take to appear.

The SDK chooses span names in the following order, from lowest to highest precedence:

1. The view controller class name followed by ` - view appearing`.
2. The navigation title or accessibility label followed by ` - view appearing`.
3. A custom name provided with `reportName(_:)`.

Class names can be Swift-mangled and are usually less useful than a navigation title or custom name.

For a SwiftUI view, set a navigation title when possible:

```swift
import SwiftUI

struct ProductsView: View {
  var body: some View {
    List {
      Text("Elastic mug")
      Text("Elastic shirt")
    }
    .navigationTitle("Products")
  }
}
```

The span appears as `Products - view appearing`.

If you cannot set a navigation title, use `reportName(_:)`:

```swift
import ElasticApm
import SwiftUI

struct ProductsView: View {
  var body: some View {
    List {
      Text("Elastic mug")
      Text("Elastic shirt")
    }
    .reportName("Products - view appearing")
  }
}
```

:::{note}
`reportName(_:)` uses the complete string you provide. Include ` - view appearing` if you want custom names to follow the SDK's default naming format.
:::

### Crash reporting [crash-reporting]

EDOT iOS captures app crashes and reports them using the OpenTelemetry [Events API](https://opentelemetry.io/docs/specs/otel/logs/event-api/).

A crash is stored on the device when it occurs. The SDK loads and exports the report on the next app launch as a log event with:

- Event name `app.crash`.
- Fatal severity.
- Exception type, message, and stack trace.
- The session ID from the crashed app session.
- The last known network connection type on supported iOS devices.

Crash reporting is enabled by default.

#### Test crash reporting [test-crash-reporting]

Crash capture is turned off while a debugger is attached. A crash triggered during a normal Xcode debug session is not recorded.

To test crash reporting:

1. In Xcode, select **Product** → **Scheme** → **Edit Scheme**.
2. Select **Run**, then open the **Info** tab.
3. Clear **Debug executable**.
4. Build and run the app.
5. Trigger the crash.
6. Launch the app again to send the pending crash report.

Alternatively, install the app, stop the Xcode session, and launch it from the device home screen before triggering the crash.

:::{note}
Crash reports are sent on the next app launch, not at the time of the crash.
:::

### System metrics [system-metrics]

EDOT iOS records app CPU and memory usage:

| Metric | Description | Unit |
| --- | --- | --- |
| `system.cpu.usage` | CPU used by the app's active threads | Percentage |
| `system.memory.usage` | Physical memory footprint of the app process | Bytes |

Both metrics include the attribute `state=app`.

### Application lifecycle events [app-lifecycle-events]

EDOT iOS creates `lifecycle` log events when the app changes state.

The `lifecycle.state` attribute can have the following values:

| Value | App transition |
| --- | --- |
| `active` | The app became active. |
| `inactive` | The app is about to become inactive. |
| `background` | The app entered the background. |
| `foreground` | The app is about to enter the foreground. |
| `terminate` | The app is about to terminate. |

## Understanding automatic-instrumentation scope [automatic-instrumentation-scope]

Automatic instrumentation captures telemetry only for the APIs and lifecycle events listed on this page. It cannot instrument:

- Custom or proprietary frameworks.
- Closed-source components without instrumentation support.
- Application-specific business logic.

If your app uses code that is not covered by automatic instrumentation, use one of the following approaches:

1. **Native OpenTelemetry support** — Some libraries include instrumentation provided by their vendor.
2. **Manual instrumentation** — Use the [OpenTelemetry-Swift APIs](manual-instrumentation.md) to create spans, metrics, and logs.

## SDK compatibility [supported-technologies]

EDOT iOS currently uses OpenTelemetry-Swift `2.2.1` or later and OpenTelemetry-Swift Core `2.3.0` or later.
