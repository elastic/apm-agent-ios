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
//   limitations under the License.import Foundation

import XCTest
import OpenTelemetrySdk
@testable import ElasticApm

class AgentConfigManagerTests : XCTestCase {
  func testRemoteConfigDisabled() {

    let manager = AgentConfigManager(resource: Resource(),
                                     config: AgentConfigBuilder().withRemoteManagement(false).build(),
                                     instrumentationConfig: InstrumentationConfigBuilder().build())
    XCTAssertNotNil(manager.central)
    let configData = manager.central.data
    XCTAssertTrue(configData.recording)
    XCTAssertNil(configData.sampleRate)
  }
}
