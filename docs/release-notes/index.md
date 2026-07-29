---
navigation_title: "EDOT iOS"
description: Release notes for the Elastic Distribution of OpenTelemetry iOS (previously Elastic APM Agent for iOS).
applies_to:
  stack:
  serverless:
    observability:
products:
  - id: cloud-serverless
  - id: observability
  - id: edot-sdk
mapped_pages:
  - https://www.elastic.co/guide/en/apm/agent/swift/current/release-notes-v1.0.2.html
  - https://www.elastic.co/guide/en/apm/agent/swift/current/release-notes-v1.0.1.html
  - https://www.elastic.co/guide/en/apm/agent/swift/current/release-notes-v1.0.0.html
---

# Elastic Distribution of OpenTelemetry iOS release notes [elastic-apm-ios-agent-release-notes]

Review the changes, fixes, and more in each version of {{edot}} iOS. 

To check for security updates, go to [Security announcements for the Elastic stack](https://discuss.elastic.co/c/announcements/security-announcements/31).

% Release notes includes only features, enhancements, and fixes. Add breaking changes, deprecations, and known issues to the applicable release notes sections. 

% version.next [elastic-apm-ios-agent-versionext-release-notes]
% **Release date:** Month day, year

% ### Features and enhancements [elastic-apm-ios-agent-versionext-features-enhancements]

% ### Fixes [elastic-apm-ios-agent-versionext-fixes]

## 2.0.2 [elastic-apm-202-release-notes]

**Release date:** July 28, 2026

### Features and enhancements [elastic-apm-ios-agent-202-features-enhancements]

* Require swift-nio-ssl 2.37.2 or later to ensure builds resolve an up-to-date version [#362](https://github.com/elastic/apm-agent-ios/pull/362)

## 2.0.1 [elastic-apm-201-release-notes]

**Release date:** May 20, 2026

### Features and enhancements [elastic-apm-ios-agent-201-features-enhancements]

* [Breaking] Disable MetricKit instrumentation and make `withAppMetricInstrumentation` a deprecated no-op because it is incompatible with OpenTelemetry-Swift 2.x metrics [#349](https://github.com/elastic/apm-agent-ios/pull/349)

## 2.0.0 [elastic-apm-200-release-notes]

**Release date:** February 24, 2026

### Features and enhancements [elastic-apm-ios-agent-200-features-enhancements]

* [Breaking] Update OpenTelemetry-Swift from 1.17.0 to 2.x and use the new `opentelemetry-swift-core` package for the API and SDK [#321](https://github.com/elastic/apm-agent-ios/pull/321)
* [Breaking] Remove `AgentConfigBuilder.addMetricFilter` and custom metric signal filtering due to upstream metrics API changes [#321](https://github.com/elastic/apm-agent-ios/pull/321)
* Deprecate MetricKit instrumentation because it is incompatible with OpenTelemetry-Swift 2.x metrics [#321](https://github.com/elastic/apm-agent-ios/pull/321)

## 1.4.0 [elastic-apm-140-release-notes]

### Features and enhancements [elastic-apm-ios-agent-140-features-enhancements]

* OpAMP support [#290](https://github.com/elastic/apm-agent-ios/pull/290)

### Fixes [elastic-apm-ios-agent-140-fixes]

* Respect custom exportUrl path [#310](https://github.com/elastic/apm-agent-ios/pull/310)

## 1.3.0 [elastic-apm-130-release-notes]

**Release date:** August 25, 2025

### Features and enhancements [elastic-apm-ios-agent-130-features-enhancements]

* [Breaking] Raise the minimum requirements to Swift 5.10, iOS 16, macOS 13, tvOS 16, and watchOS 10 [#281](https://github.com/elastic/apm-agent-ios/pull/281)
* Updated OpenTelemetry-Swift to version 1.17.0
* Allow signal filters to be mutable [#266](https://github.com/elastic/apm-agent-ios/pull/266)
* Added mutableLogRecord so attributes can be appended during filtering [#271](https://github.com/elastic/apm-agent-ios/pull/271)
* Adds support for custom collector paths [#267](https://github.com/elastic/apm-agent-ios/pull/276)
* Signal interceptors [#283](https://github.com/elastic/apm-agent-ios/pull/283)

## 1.2.1 [elastic-apm-121-release-notes]

**Release date:** February 21, 2025

### Features and enhancements [elastic-apm-ios-agent-121-features-enhancements]

* Updated OpenTelemetry-Swift to version 1.13.0

### Fixes [elastic-apm-ios-agent-121-fixes]

* Make crash reports respect the configured connection type [#249](https://github.com/elastic/apm-agent-ios/pull/249)

## 1.2.0 [elastic-apm-120-release-notes]

### Features and enhancements [elastic-apm-ios-agent-120-features-enhancements]

* Bumped Reachability to version 5.2.4 [#245](https://github.com/elastic/apm-agent-ios/pull/245)
* Updated OpenTelemetry-Swift to version 1.12.1

## 1.1.0 [elastic-apm-110-release-notes]

### Features and enhancements [elastic-apm-ios-agent-110-features-enhancements]

* Updated OpenTelemetry-Swift to version 1.11.0

## 1.0.5 [elastic-apm-105-release-notes]

### Fixes [elastic-apm-ios-agent-105-fixes]

* Fixes HTTP connection type [#239](https://github.com/elastic/apm-agent-ios/pull/239)

## 1.0.4 [elastic-apm-104-release-notes]

### Fixes [elastic-apm-ios-agent-104-fixes]

* Updated privacy manifest [#233](https://github.com/elastic/apm-agent-ios/pull/233)

## 1.0.3 [elastic-apm-103-release-notes]

### Features and enhancements [elastic-apm-ios-agent-103-features-enhancements]

* Added options to use HTTP instead of GRPC for Exporters [#228](https://github.com/elastic/apm-agent-ios/pull/228)

### Fixes [elastic-apm-ios-agent-103-fixes]

* Fixed ntp clock logging to only occur once. [#229](https://github.com/elastic/apm-agent-ios/pull/229)

## 1.0.2 [elastic-apm-ios-agent-102-release-notes]

### Features and enhancements [elastic-apm-ios-agent-102-features-enhancements]

* Added Privacy Manifest file [#217](https://github.com/elastic/apm-agent-ios/pull/217).

## 1.0.1 [elastic-apm-ios-agent-101-release-notes]

### Fixes [elastic-apm-ios-agent-101-fixes]

* Fixed memory leaks related to NTP usage [#212](https://github.com/elastic/apm-agent-ios/pull/212).

## 1.0.0 [elastic-apm-ios-agent-100-release-notes]

### Features and enhancements [elastic-apm-ios-agent-100-features-enhancements]

* Added network status to all signals [#202](https://github.com/elastic/apm-agent-ios/pull/202).
* Added session.id to crash reports [#197](https://github.com/elastic/apm-agent-ios/pull/197).
