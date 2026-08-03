---
navigation_title: Manual instrumentation
description: Learn how to manually instrument iOS applications using EDOT iOS to create spans, metrics, and logs.
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
---

# Manual instrumentation using EDOT iOS

Learn how to manually instrument your app using the OpenTelemetry-Swift APIs configured by EDOT iOS.

Manual instrumentation allows you to capture app-specific operations that [automatic instrumentation](automatic-instrumentation.md) can't infer, such as:

- A user completing a checkout flow
- A local database query
- The number of items added to a cart
- A log record that explains why an operation failed

## OpenTelemetry APIs [opentelemetry-apis]

After completing the [setup](getting-started.md), EDOT iOS registers global tracer, meter, and logger providers. Access them through the `OpenTelemetry` instance:

```swift
import OpenTelemetryApi

let tracer = OpenTelemetry.instance.tracerProvider.get(
  instrumentationName: "com.example.my-app"
)

let meter = OpenTelemetry.instance.meterProvider
  .meterBuilder(name: "com.example.my-app")
  .build()

let logger = OpenTelemetry.instance.loggerProvider
  .loggerBuilder(instrumentationScopeName: "com.example.my-app")
  .build()
```

Use a stable instrumentation scope name that identifies the library or app component creating the telemetry.

## Create spans [create-spans]

A [span](https://opentelemetry.io/docs/concepts/signals/traces/#spans) represents an operation with a start and end time.

The following example creates a span around an operation:

```swift
import OpenTelemetryApi

func loadProducts() {
  let tracer = OpenTelemetry.instance.tracerProvider.get(
    instrumentationName: "com.example.my-app"
  )

  let span = tracer.spanBuilder(spanName: "load-products").startSpan()
  defer {
    span.end()
  }

  // Run the operation you want to measure.
}
```

Always end spans. A `defer` block is useful when an operation can return from multiple code paths.

### Create parent and child spans [parent-child-spans]

Use parent and child spans to represent work performed as part of a larger operation:

```swift
import OpenTelemetryApi

func refreshProducts() {
  let tracer = OpenTelemetry.instance.tracerProvider.get(
    instrumentationName: "com.example.my-app"
  )

  let parentSpan = tracer.spanBuilder(spanName: "refresh-products").startSpan()
  defer {
    parentSpan.end()
  }

  let childSpan = tracer.spanBuilder(spanName: "read-product-cache")
    .setParent(parentSpan)
    .startSpan()

  // Read the local cache.

  childSpan.end()
}
```

Setting the parent explicitly keeps the relationship clear when work crosses queues or asynchronous boundaries.

### Add attributes and events [span-attributes-events]

[Attributes](https://opentelemetry.io/docs/concepts/signals/traces/#attributes) add queryable context to a span. Events identify a meaningful point in time during the operation:

```swift
import OpenTelemetryApi

func loadProducts() {
  let tracer = OpenTelemetry.instance.tracerProvider.get(
    instrumentationName: "com.example.my-app"
  )
  let span = tracer.spanBuilder(spanName: "load-products").startSpan()
  defer {
    span.end()
  }

  span.setAttribute(key: "app.screen", value: "products")
  span.setAttribute(key: "product.count", value: 42)

  span.addEvent(
    name: "cache.miss",
    attributes: [
      "cache.name": .string("products"),
    ]
  )
}
```

Avoid putting secrets, personal data, or values with unbounded cardinality in attributes.

### Record errors [record-errors]

Record an exception event and set the span status when an operation fails:

```swift
import OpenTelemetryApi

func refreshProducts() async throws {
  let tracer = OpenTelemetry.instance.tracerProvider.get(
    instrumentationName: "com.example.my-app"
  )
  let span = tracer.spanBuilder(spanName: "refresh-products").startSpan()
  defer {
    span.end()
  }

  do {
    try await loadProducts()
    span.status = .ok
  } catch {
    span.recordException(error)
    span.status = .error(description: error.localizedDescription)
    throw error
  }
}
```

Recording an exception does not end the span. End it after all work and error handling is complete.

## Create metrics [create-metrics]

A [metric](https://opentelemetry.io/docs/concepts/signals/metrics/) measures a value over time. The following example records the number of products added to a cart:

```swift
import OpenTelemetryApi

func recordProductAdded() {
  let meter = OpenTelemetry.instance.meterProvider
    .meterBuilder(name: "com.example.my-app")
    .build()

  var productsAdded = meter.counterBuilder(name: "app.cart.products_added")
    .build()

  productsAdded.add(
    value: 1,
    attributes: [
      "product.category": .string("accessories"),
    ]
  )
}
```

Choose the instrument type that matches the value you are recording. Refer to the [OpenTelemetry metrics API](https://opentelemetry.io/docs/specs/otel/metrics/api/) for counters, histograms, gauges, and other instruments.

## Create logs [create-logs]

A log record describes an event that occurs in your app:

```swift
import OpenTelemetryApi

func logProductsRefreshed() {
  let logger = OpenTelemetry.instance.loggerProvider
    .loggerBuilder(instrumentationScopeName: "com.example.my-app")
    .build()

  logger.logRecordBuilder()
    .setSeverity(.info)
    .setBody(.string("Products refreshed"))
    .setAttributes([
      "product.count": .int(42),
    ])
    .emit()
}
```

EDOT iOS adds the current `session.id` to exported log records. If a log is related to a span, set its span context so you can correlate both signals:

```swift
import OpenTelemetryApi

func logRefreshFailure() {
  let tracer = OpenTelemetry.instance.tracerProvider.get(
    instrumentationName: "com.example.my-app"
  )
  let logger = OpenTelemetry.instance.loggerProvider
    .loggerBuilder(instrumentationScopeName: "com.example.my-app")
    .build()
  let span = tracer.spanBuilder(spanName: "refresh-products").startSpan()

  logger.logRecordBuilder()
    .setSpanContext(span.context)
    .setSeverity(.error)
    .setBody(.string("Failed to refresh products"))
    .emit()

  span.end()
}
```

## When to use manual instrumentation [manual-instrumentation-scope]

Use manual instrumentation for custom or proprietary code, closed-source components without instrumentation support, and application-specific business logic.

Before adding custom instrumentation for a framework or Apple API, review [Automatic instrumentation](automatic-instrumentation.md). EDOT iOS might already generate the telemetry you need.

For more details about the upstream APIs, refer to:

- [OpenTelemetry Swift instrumentation](https://opentelemetry.io/docs/languages/swift/instrumentation/)
- [OpenTelemetry-Swift examples](https://github.com/open-telemetry/opentelemetry-swift/tree/main/Examples)
- [OpenTelemetry concepts](https://opentelemetry.io/docs/concepts/)
