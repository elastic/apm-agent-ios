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
import PersistenceExporter

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
    enableCrashReporting = enable
    return self
  }

  public func withURLSessionInstrumentation(_ enable: Bool) -> Self {
    enableURLSessionInstrumentation = enable
    return self
  }

  public func withViewControllerInstrumentation(_ enable: Bool) -> Self {
    enableViewControllerInstrumentation = enable
    return self
  }

  @available(*, deprecated, message: "App Metrics instrumentation temporarily deprecated. New version coming soon.")
  public func withAppMetricInstrumentation(_: Bool) -> Self {
    self
  }

  public func withSystemMetrics(_ enable: Bool) -> Self {
    enableSystemMetrics = enable
    return self
  }

  public func withLifecycleEvents(_ enable: Bool) -> Self {
    enableLifecycleEvents = enable
    return self
  }

  public func withPersistentStorageConfiguration(_ config: PersistencePerformancePreset) -> Self {
    persistentStorageConfig = config
    return self
  }

  public func build() -> InstrumentationConfiguration {
    var config = InstrumentationConfiguration()

    if let enableCrashReporting {
      config.enableCrashReporting = enableCrashReporting
    }

    if let enableURLSessionInstrumentation {
      config.enableURLSessionInstrumentation = enableURLSessionInstrumentation
    }

    if let enableViewControllerInstrumentation {
      config.enableViewControllerInstrumentation = enableViewControllerInstrumentation
    }

    if let enableAppMetricInstrumentation {
      config.enableAppMetricInstrumentation = enableAppMetricInstrumentation
    }

    if let enableSystemMetrics {
      config.enableSystemMetrics = enableSystemMetrics
    }

    if let enableLifecycleEvents {
      config.enableLifecycleEvents = enableLifecycleEvents
    }

    if let persistentStorageConfig {
      config.storageConfiguration = persistentStorageConfig
    }

    return config
  }
}
