---
navigation_title: Get started
description: Set up the Elastic Distribution of OpenTelemetry iOS (EDOT iOS) to send data to Elastic.
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
  - https://www.elastic.co/guide/en/apm/agent/swift/current/setup.html
---

# Get started with EDOT iOS [setup]

Set up the Elastic Distribution of OpenTelemetry iOS (EDOT iOS) in your app and explore your app's data in {{kib}}.

## Requirements [requirements]

| Requirement | Minimum version |
| --- | --- |
| Swift | 5.10 |
| iOS | 16 |

You also need a reachable OpenTelemetry Protocol (OTLP) endpoint provided by an [Elastic Agent OTLP endpoint](elastic-agent://reference/edot-collector/modes.md#edot-collector-as-gateway).

## Add the SDK dependency [add-agent-dependency]

Add EDOT iOS to your app using Swift Package Manager.

### Add the package in Xcode [add-package-xcode]

To add EDOT iOS to an Xcode project:

1. In Xcode, select **File** → **Add Package Dependencies**.
2. Enter `https://github.com/elastic/apm-agent-ios.git` in the package URL field.
3. Select the version rule that matches your dependency policy.
4. Add the `ElasticApm` product to your application target.

Refer to Apple's [Adding package dependencies to your app](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app) guide for more information.

### Add the package in `Package.swift` [add-package-manifest]

Add the package and the `ElasticApm` product to your target:

```swift
// swift-tools-version: 5.10

import PackageDescription

let package = Package(
  name: "MyApp",
  dependencies: [
    .package(
      url: "https://github.com/elastic/apm-agent-ios.git",
      from: "2.1.0"
    ),
  ],
  targets: [
    .target(
      name: "MyApp",
      dependencies: [
        .product(name: "ElasticApm", package: "apm-agent-ios"),
      ]
    ),
  ]
)
```

## Agent setup [initialize]

Initialize EDOT iOS as early as possible in your app lifecycle. The following examples send data over OTLP/HTTP and authenticate with an APM agent key:

```swift
import ElasticApm
import Foundation

let configuration = AgentConfigBuilder()
  .withExportUrl(URL(string: "https://your-otlp-endpoint")!) // <1>
  .withApiKey("your-api-key") // <2>
  .build()

ElasticApmAgent.start(with: configuration)
```

OTLP/HTTP is the default transport. Use `.useConnectionType(.grpc)` only when
your OTLP endpoint requires gRPC, usually on port `4317`. The URL scheme selects
transport security: `https` enables TLS and `http` uses plaintext.

1. Replace this value with your OTLP endpoint. For deployment options, refer to [OpenTelemetry ingest paths](docs-content://solutions/observability/apm/opentelemetry/index.md).
2. Create an [APM agent key for EDOT SDKs](docs-content://solutions/observability/apm/opentelemetry/create-apm-agent-key-for-edot-sdks.md). You can use a [secret token](configuration.md#secretToken) instead when your deployment requires one.

### SwiftUI applications [swiftui-setup]

For a SwiftUI app, initialize EDOT iOS from an application delegate:

```swift
import ElasticApm
import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    let configuration = AgentConfigBuilder()
      .withExportUrl(URL(string: "https://your-otlp-endpoint")!)
      .withApiKey("your-api-key")
      .build()

    ElasticApmAgent.start(with: configuration)
    return true
  }
}

@main
struct MyApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}
```

### UIKit applications [uikit-setup]

For a UIKit app, initialize EDOT iOS from `application(_:didFinishLaunchingWithOptions:)`:

```swift
import ElasticApm
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let configuration = AgentConfigBuilder()
      .withExportUrl(URL(string: "https://your-otlp-endpoint")!)
      .withApiKey("your-api-key")
      .build()

    ElasticApmAgent.start(with: configuration)
    return true
  }
}
```

## Start sending telemetry [start-sending-telemetry]

With EDOT iOS initialized, you can start sending telemetry to Elastic.

### Generate telemetry [generate-telemetry]

The following example generates a span through [manual instrumentation](manual-instrumentation.md):

```swift
import OpenTelemetryApi

let tracer = OpenTelemetry.instance.tracerProvider.get(
  instrumentationName: "com.example.my-app"
)

let span = tracer.spanBuilder(spanName: "load-products").startSpan()
span.setAttribute(key: "app.screen", value: "products")

// Run the operation you want to measure.

span.end()
```

EDOT iOS can also generate telemetry on your behalf. For example, [URLSession instrumentation](automatic-instrumentation.md#urlsession-instrumentation) creates spans for outgoing network requests without requiring manual span code.

### Visualize telemetry [visualize-telemetry]

The [iOS OpenTelemetry Assets](integration-docs://reference/otel_ios_dashboards.md) integration provides {{kib}} dashboards designed for telemetry from iOS applications. These dashboards provide an overview of application health and dedicated views for spans, crashes, sessions, and other iOS telemetry.

After your app has sent telemetry data, either [manually](manual-instrumentation.md) or [automatically](automatic-instrumentation.md), install the integration's content package to visualize it in {{kib}}.

#### Install the content package

1. In {{kib}}, search for **iOS OpenTelemetry Assets** in the [global search field](docs-content://explore-analyze/find-and-organize/find-apps-and-objects.md).
2. Open it and click **Install** to add the iOS dashboards to your {{kib}} instance.

#### Explore your data in the dashboard

Once the content package is installed, open the **[iOS OTel] Application Overview** dashboard:

1. In {{kib}}, search for **Dashboards** in the [global search field](docs-content://explore-analyze/find-and-organize/find-apps-and-objects.md).
2. Search for **iOS OTel** and open the **[iOS OTel] Application Overview** dashboard.
3. Select your application by clicking its name in the **Applications** table of the **Overview** section.

:::{image} images/span-visualization/application-overview-dashboard.png
:alt: Application Overview Dashboard
:screenshot:
:::

The dashboard provides a high-level view of your app's health, including span performance, crash analysis, and session-level insights.

#### View trace waterfall details

To inspect individual span traces in detail, go to a panel that shows a list of spans in the dashboard and click its **Explore in Discover** button.

:::{image} images/span-visualization/explore-spans-in-discover.png
:alt: Explore in Discover
:screenshot:
:::

In Discover, expand the details for one of the spans by clicking the expand icon on the left.

:::{image} images/span-visualization/open-span-details.png
:alt: Open span details
:screenshot:
:::

You'll see the trace waterfall UI, showing the full span hierarchy and timing. You can expand it to fullscreen and drill down into further details from there.

:::{image} images/span-visualization/trace-waterfall-ui.png
:alt: Trace waterfall UI
:screenshot:
:::

#### Learn more

- [View crash details](integration-docs://reference/otel_ios_dashboards.md#viewing-details-from-a-crash) — Learn how to visualize and drill into iOS crash reports in the dashboard.
- [Troubleshoot dashboard issues](integration-docs://reference/otel_ios_dashboards.md#troubleshooting) — Find solutions to common issues with the {{kib}} dashboard experience.

## What's next? [whats-next]

- This guide uses the minimum configuration needed to initialize EDOT iOS. Refer to [Configuration](configuration.md) to customize connectivity, authentication, sampling, storage, and instrumentation.
- Review [Automatic instrumentation](automatic-instrumentation.md) to learn what EDOT iOS captures on your behalf.
- Use [Manual instrumentation](manual-instrumentation.md) to create spans, metrics, and logs for your app's business logic.
- If data does not appear in {{kib}}, refer to [Troubleshooting](docs-content://troubleshoot/ingest/opentelemetry/edot-sdks/ios/index.md).
