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

public struct InstrumentationConfiguration {
  public var enableCrashReporting = true
  public var enableURLSessionInstrumentation = true
  public var enableViewControllerInstrumentation = true
  public var enableAppMetricInstrumentation = true
  public var enableSystemMetrics = true
  public var enableLifecycleEvents = true
  public var storageConfiguration: PersistencePerformancePreset = .default
  public init() {}
}
