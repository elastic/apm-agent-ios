---
navigation_title: Supported technologies
description: Technologies supported by the Elastic Distribution of OpenTelemetry iOS.
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
  - https://www.elastic.co/guide/en/apm/agent/swift/current/supported-technologies.html
---

# Technologies supported by EDOT iOS SDK [supported-technologies]

The Elastic Distribution of OpenTelemetry iOS automatically instruments various APIs, frameworks, and application servers. This section lists all supported technologies.

:::{note}
**Understanding auto-instrumentation scope**

Auto-instrumentation automatically captures telemetry for the frameworks and libraries listed on this page. However, it cannot instrument:

- Custom or proprietary frameworks and libraries
- Closed-source components without instrumentation support
- Application-specific business logic

If your application uses technologies not covered by auto-instrumentation, you have two options:

1. **Native OpenTelemetry support** — Some frameworks and libraries include built-in OpenTelemetry instrumentation provided by the vendor.
2. **Manual instrumentation** — Use the [OpenTelemetry API](https://opentelemetry.io/docs/languages/swift/instrumentation/) to add custom spans, metrics, and logs for unsupported components.
:::

| Framework | Version |
| --- | --- |
| OpenTelemetry-Swift | 1.17.0 |

