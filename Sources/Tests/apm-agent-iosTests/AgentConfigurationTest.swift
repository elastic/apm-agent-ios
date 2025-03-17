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

import XCTest
@testable import ElasticApm


class AgentConfigurationTest : XCTestCase {
  func testBasicConfiguration() {
    let agentConfiguration = AgentConfigBuilder()
      .withServerUrl(URL(string: "https://localhost:443")!)
      .build()
    XCTAssertEqual(agentConfiguration.collectorHost, "localhost")
    XCTAssertEqual(agentConfiguration.collectorPort, 443)
    XCTAssertEqual(agentConfiguration.collectorTLS, true)
    XCTAssertEqual(agentConfiguration.connectionType, .grpc)
  }

  func testEDOTUrls() {
    let agentConfiguration = AgentConfigBuilder()
      .withExportUrl(URL(string:"https://localhost:443")!)
      .withManagementUrl(URL(string:"https://management.com:8200/v1/management")!)
      .build()
    let managementUrlComponents = agentConfiguration.managementUrlComponents()
    XCTAssertEqual(managementUrlComponents.host, "management.com")
    XCTAssertEqual(managementUrlComponents.port, 8200)
    XCTAssertEqual(managementUrlComponents.path, "/v1/management")
    XCTAssertEqual(managementUrlComponents.scheme, "https")
    XCTAssertEqual(agentConfiguration.collectorHost, "localhost")
    XCTAssertEqual(agentConfiguration.collectorPort, 443)
    XCTAssertEqual(agentConfiguration.collectorTLS, true)
    XCTAssertEqual(agentConfiguration.connectionType, .grpc)
  }

 func testEDOTUrlAndNoManagementUrl() {
    let agentConfiguration = AgentConfigBuilder()
      .withExportUrl(URL(string:"https://localhost:443")!)
      .build()

   XCTAssertEqual(agentConfiguration.managementUrlComponents().url, URL(string:"https://localhost:443/config/v1/agents"))
    XCTAssertEqual(agentConfiguration.collectorHost, "localhost")
    XCTAssertEqual(agentConfiguration.collectorPort, 443)
   XCTAssertEqual(agentConfiguration.collectorTLS, true)
 }

  func testEDOTUrlsWithDeprecatedServerUrl() {
    let agentConfiguration = AgentConfigBuilder()
      .withServerUrl(URL(string:"http://127.0.0.1:8080")!)
      .withExportUrl(URL(string:"https://localhost:443")!)
      .withManagementUrl(URL(string:"https://management.com:8200/v1/management")!)
      .build()

    let managementUrlComponents = agentConfiguration.managementUrlComponents()
    XCTAssertEqual(managementUrlComponents.host, "management.com")
    XCTAssertEqual(managementUrlComponents.port, 8200)
    XCTAssertEqual(managementUrlComponents.path, "/v1/management")
    XCTAssertEqual(managementUrlComponents.scheme, "https")
    XCTAssertEqual(agentConfiguration.collectorHost, "localhost")
    XCTAssertEqual(agentConfiguration.collectorPort, 443)
    XCTAssertEqual(agentConfiguration.collectorTLS, true)
    XCTAssertEqual(agentConfiguration.connectionType, .grpc)
  }
}


