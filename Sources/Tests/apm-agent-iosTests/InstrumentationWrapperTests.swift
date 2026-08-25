// Copyright © 2026 Elasticsearch BV
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

import OpenTelemetrySdk
import URLSessionInstrumentation
import XCTest

@testable import ElasticApm

final class InstrumentationWrapperTests: XCTestCase {
  func testDefaultURLSessionConfigurationUsesStableHTTPConventions() {
    let configuration = makeWrapper(useLegacyAttributeNames: false)
      .makeURLSessionInstrumentationConfiguration()

    guard case .stable = configuration.semanticConvention else {
      return XCTFail("Default URLSession instrumentation must use stable HTTP conventions")
    }
  }

  func testLegacyURLSessionConfigurationUsesOldHTTPConventions() {
    let configuration = makeWrapper(useLegacyAttributeNames: true)
      .makeURLSessionInstrumentationConfiguration()

    guard case .old = configuration.semanticConvention else {
      return XCTFail("Legacy URLSession instrumentation must use old HTTP conventions")
    }
  }

  private func makeWrapper(useLegacyAttributeNames: Bool) -> InstrumentationWrapper {
    let agentConfiguration = AgentConfigBuilder()
      .withRemoteManagement(false)
      .useLegacyAttributeNames(useLegacyAttributeNames)
      .build()
    let instrumentationConfiguration = InstrumentationConfigBuilder()
      .withLifecycleEvents(false)
      .withViewControllerInstrumentation(false)
      .withSystemMetrics(false)
      .build()
    let manager = AgentConfigManager(
      resource: Resource(),
      config: agentConfiguration,
      instrumentationConfig: instrumentationConfiguration
    )
    return InstrumentationWrapper(config: manager)
  }
}
