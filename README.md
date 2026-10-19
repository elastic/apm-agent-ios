[![Build and Test](https://github.com/elastic/apm-agent-ios/actions/workflows/build-and-test.yml/badge.svg)](https://github.com/elastic/apm-agent-ios/actions/workflows/build-and-test.yml)

# EDOT iOS
The Elastic Distribution of OpenTelemetry iOS (EDOT iOS) is the OpenTelemetry-based SDK for iOS apps.

## Documentation

Read the [EDOT iOS documentation](https://www.elastic.co/docs/reference/opentelemetry/edot-sdks/ios).

## Try it out

Follow the [Demo application guide](https://github.com/elastic/ios-agent-demo) to set up a test environment and take a quick
look at the agent's functionalities.

## Notes

### disabling noisy logs

- CoreTelephony in simulator
```xcrun simctl spawn booted log config --mode "level:off" --subsystem com.apple.CoreTelephony```

- Layout Constraints warnings
```xcrun simctl spawn booted log config --mode "level:off" --subsystem com.apple.UIKit```
