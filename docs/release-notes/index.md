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

## 1.0.2 [elastic-apm-ios-agent-102-release-notes]

### Features and enhancements [elastic-apm-ios-agent-102-features-enhancements]

* Added Privacy Manifest file [#217].

## 1.0.1 [elastic-apm-ios-agent-101-release-notes]

### Fixes [elastic-apm-ios-agent-101-fixes]

* Fixed memory leaks related to NTP usage [#212].

## 1.0.0 [elastic-apm-ios-agent-100-release-notes]

### Features and enhancements [elastic-apm-ios-agent-100-features-enhancements]

* Added network status to all signals [#202].
* Added session.id to crash reports [#195].
