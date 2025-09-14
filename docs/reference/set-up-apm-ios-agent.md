---
navigation_title: Setup
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

# Set up the APM iOS Agent [setup]

Learn how to set up and configure the Elastic Distribution of OpenTelemetry iOS (EDOT iOS) to instrument your application.

## Requirements [requirements]

This project requires Swift `5.10`, and is intended for use in Swift-base mobile apps.

Other platform requires:

| platform | version |
| --- | --- |
| `iOS` | `16` |
| `macOS` | `13` |
| `tvOS` | `16` |
| `watchOS` | `10` |

## Add the SDK dependency [add-agent-dependency]

Add the Elastic Distribution of OpenTelemetry iOS to your Xcode project or your `Package.swift`.

Here are instructions for adding a [package dependency](https://developer.apple.com/documentation/swift_packages/adding_package_dependencies_to_your_app) to a standard Xcode project.

Details of adding dependencies to your Package.swift can be found on [*Add a Dependency on Another Swift Package*](https://developer.apple.com/documentation/xcode/creating_a_standalone_swift_package_with_xcode#3578941). The following is a helpful code snippet:

`package.swift`:

```swift
Package(
    dependencies:[
         .package(name: "apm-agent-ios", url: "https://github.com/elastic/apm-agent-ios.git", from: "1.2.0"),
    ],
  targets:[
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "ElasticApm", package: "apm-agent-ios")
        ]
    ),
])
```


## Initialize the SDK [initialize]

After you've added the SDK as a dependency, initialize it.

If you’re using `SwiftUI` to build your app add the following to your `App.swift`:

```swift
import SwiftUI
import ElasticApm

class AppDelegate : NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        var config = AgentConfigBuilder()
            .withServerUrl(URL(string:"http://127.0.0.1:8200")) <1>
            .withSecretToken("<SecretToken>") <2>
            .build()

        ElasticApmAgent.start(with: config)
        return true
    }
}

@main
struct MyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    init() {
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

1. APM Server URL
2. Set the secret token for APM server connection

If you’re not using `SwiftUI` you can alternatively add the same thing to your AppDelegate file:

`AppDelegate.swift`

```swift
import UIKit
import ElasticApm
@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
var config = AgentConfigBuilder()
                       .withServerUrl(URL(string:"http://127.0.0.1:8200")) <1>
                       .withSecretToken("<SecretToken>") <2>
                       .build()
        ElasticApmAgent.start(with: config)
        return true
    }
}
```

1. APM Server URL
2. Set the secret token for APM server connection


