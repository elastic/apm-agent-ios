# User Action Instrumentation

User action instrumentation consist of view controller instrumentation & tap instrumentation.
These both capture actions in the form of spans from UIKit and from SwiftUI, but with some limitations. 


## View Controller Insturmentation
This instrumentation create a span on `viewWillAppear`/`viewDidLoad` and ends on `ViewDidAppear`.
If multiple view controllers are loaded simultaneously, the trace will begin with the first view controller loading and end when that view controller calls `viewDidAppear`. 

### Span Naming

**For standard UIKit:**

View controllers the span naming priority is as followed :

`viewController.accessibilityLabel` -> `viewController.navigationItem.title` -> `type(of:viewController)`

The automatically generated names will be suffixed with ` - view appearing`

**For SwiftUI:**
Due to constraints of the SwiftUI framework, it's not possible to access accessibility items from the instrumentation.
Default naming for SwiftUI elements will only consist of `type(of:viewController)` appended with `- view appearing`

A convenience method is provided to allow for dynamic renaming of the span while a view is being loaded: 

```
@available(iOS 13.0, *)
public extension View {
    func reportName(_ name: String) -> Self {
        OpenTelemetry.instance.contextProvider.activeSpan?.name = name
        return self
    }
}
```

Apply this extension to a view in the targeted `SwiftUI.View`'s `body` attribute: 
```
struct MainView : View {
    var body : some View {
        View {
        }.reportName("My Main View - view appearing")
    }
}
```

The default suffix, ` - view appearing` will not be automatically applied when using the `reportName` API.


## Tap instrumentation
The tap instrumentation uses the UIApplicationDelegate's `sendEvent:` API to capture interactions with the UI. 

Default instrumentation starts spans for all `touch` event types, but can be configured using `UIApplicationInstrumentationConfiguration.swift`.

Spans will only be created at the `.ended` touch phase, and are terminated after half a second, or another tap occurs.

Touch spans will be named using the following format: 

`Tapped {view} in {viewController}`

The name of the view will use the accessibilty label of the touch's view, or the nearest superview with an accessibility label, or the class name of the view, `type(of: view)`.
The view controller name is captured similarly to the view controller instrumentation (described above), but the `reportName` api provided for SwiftUI will not work for tap instrumentation due to timing issues.

Due to limitations of SwiftUI there is not yet a way to set a custom name for taps. 