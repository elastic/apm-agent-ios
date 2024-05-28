// Copyright © 2023 Elasticsearch BV
//
//   Licensed under the Apache License, Version 2.0 (the "License");
//   you may not use this file except in compliance with the License.
//   You may obtain a copy of the License at
//
//       http://www.apache.org/licenses/LICENSE-2.0
//
//   Unless required by applicable law or agreed to in writing, software
//   distributed under the License is distributed on an "AS IS" BASIS,
//   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//   See the License for the specific language governing permissions and
//   limitations under the License.

import Foundation
@_implementationOnly import PersistenceExporter


public enum PersistentStorageConfigurationOption {
  case lowImpact
  case instantDelivery
}

public class InstrumentationConfigBuilder {
  var enableCrashReporting: Bool?
  var enableURLSessionInstrumentation: Bool?
  var enableViewControllerInstrumentation: Bool?
  var enableAppMetricInstrumentation: Bool?
  var enableSystemMetrics: Bool?
  var enableLifecycleEvents: Bool?
  var persistentStorageConfig: PersistencePerformancePreset?

  public init() {}

  public func withCrashReporting(_ enable: Bool) -> Self {
    self.enableCrashReporting = enable
    return self
  }

  public func withURLSessionInstrumentation(_ enable: Bool) -> Self {
    self.enableURLSessionInstrumentation = enable
    return self
  }

  public func withViewControllerInstrumentation(_ enable: Bool) -> Self {
    self.enableViewControllerInstrumentation = enable
    return self
  }
  public func withAppMetricInstrumentation(_ enable: Bool) -> Self {
    self.enableAppMetricInstrumentation = enable
    return self
  }

  public func withSystemMetrics(_ enable: Bool) -> Self {
    self.enableSystemMetrics = enable
    return self
  }

  public func withLifecycleEvents(_ enable: Bool) -> Self {
    self.enableLifecycleEvents = enable
    return self
  }

  public func withPersistentStorageConfiguration(_ option: PersistentStorageConfigurationOption = .lowImpact) -> Self {
    switch option {
    case .instantDelivery:
      self.persistentStorageConfig = .instantDataDelivery
    default:
      self.persistentStorageConfig = .lowRuntimeImpact
    }
    return self
  }

  public func build() -> InstrumentationConfiguration {
    var config = InstrumentationConfiguration()

    if let enableCrashReporting = self.enableCrashReporting {
      config.enableCrashReporting = enableCrashReporting
    }

    if let enableURLSessionInstrumentation = self.enableURLSessionInstrumentation {
      config.enableURLSessionInstrumentation = enableURLSessionInstrumentation
    }

    if let enableViewControllerInstrumentation = self.enableViewControllerInstrumentation {
      config.enableViewControllerInstrumentation = enableViewControllerInstrumentation
    }

    if let enableAppMetricInstrumentation = self.enableAppMetricInstrumentation {
      config.enableAppMetricInstrumentation = enableAppMetricInstrumentation
    }

    if let enableSystemMetrics = self.enableSystemMetrics {
      config.enableSystemMetrics = enableSystemMetrics
    }

    if let enableLifecycleEvents = self.enableLifecycleEvents {
      config.enableLifecycleEvents = enableLifecycleEvents
    }

    if let persistentStorageConfig = self.persistentStorageConfig {
      config.storageConfiguration = persistentStorageConfig
    }

    return config
  }
}
