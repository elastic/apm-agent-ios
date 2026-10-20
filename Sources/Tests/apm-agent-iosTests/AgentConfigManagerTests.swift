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
import ElasticApmTestSupport
import OpenTelemetrySdk
@testable import ElasticApm

class AgentConfigManagerTests : XCTestCase {
  func testRemoteConfigDisabled() {
    let configuration = AgentConfigBuilder().build()
    XCTAssertFalse(configuration.enableRemoteManagement)
    XCTAssertFalse(AgentConfiguration().enableRemoteManagement)

    let manager = AgentConfigManager(resource: Resource(),
                                     config: configuration,
                                     instrumentationConfig: InstrumentationConfigBuilder().build())
    XCTAssertNil((manager.centralConfigManager as? ElasticAgentConfigManager)?.fetcher)
    XCTAssertTrue(manager.centralConfigManager is ElasticAgentConfigManager)
    XCTAssertEqual(manager.registeredEndpointCount, 0)
    XCTAssertNotNil(manager.central)
    let configData = manager.central.data
    XCTAssertTrue(configData.recording)
    XCTAssertNil(configData.sampleRate)
  }

  #if os(iOS) || os(macOS)
    func testEnabledLegacyPollRegistersOnlyItsManagementURL() throws {
      let server = LoopbackHTTPTestServer()
      try server.start()
      defer { server.stop() }

      let exportURL = server.baseURL.appendingPathComponent("otlp")
      for managementURL in [nil, server.baseURL.appendingPathComponent("custom/config")] {
        let builder = AgentConfigBuilder()
          .withExportUrl(exportURL)
          .withRemoteManagement(true)
        if let managementURL {
          _ = builder.withManagementUrl(managementURL)
        }
        let configuration = builder.build()
        let manager = AgentConfigManager(
          resource: Resource(),
          config: configuration,
          instrumentationConfig: InstrumentationConfigBuilder().build())
        let legacyManager = try XCTUnwrap(manager.centralConfigManager as? ElasticAgentConfigManager)
        let fetcher = try XCTUnwrap(legacyManager.fetcher)
        let managementURL = try XCTUnwrap(configuration.managementUrlComponents().url)
        let requestURL = try XCTUnwrap(fetcher.buildCentralConfigRequest()?.url)

        XCTAssertTrue(manager.isRegistered(managementURL))
        XCTAssertTrue(manager.isRegistered(requestURL))
        XCTAssertFalse(manager.isRegistered(exportURL.appendingPathComponent("application")))
        XCTAssertEqual(manager.registeredEndpointCount, 1)
        if managementURL.path == "/custom/config" {
          XCTAssertFalse(manager.isRegistered(exportURL.appendingPathComponent("config/v1/agents")))
        }
      }
    }

    func testDeprecatedConfigurationPropertyEnablesLegacyPoll() throws {
      let server = LoopbackHTTPTestServer()
      try server.start()
      defer { server.stop() }
      var configuration = AgentConfigBuilder().withExportUrl(server.baseURL).build()
      configuration.enableRemoteManagement = true
      let manager = AgentConfigManager(
        resource: Resource(),
        config: configuration,
        instrumentationConfig: InstrumentationConfigBuilder().build())

      XCTAssertNotNil((manager.centralConfigManager as? ElasticAgentConfigManager)?.fetcher)
      XCTAssertTrue(manager.isRegistered(server.baseURL.appendingPathComponent("config/v1/agents")))
    }

    func testOpAMPSelectionIgnoresLegacyRemoteManagementSetting() throws {
      let server = LoopbackHTTPTestServer()
      try server.start()
      defer { server.stop() }
      for enabled in [false, true] {
        let manager = AgentConfigManager(
          resource: Resource(),
          config: AgentConfigBuilder()
            .withExportUrl(server.baseURL)
            .withManagementUrl(server.baseURL.appendingPathComponent("opamp"))
            .withRemoteManagement(enabled)
            .useOpAMP()
            .build(),
          instrumentationConfig: InstrumentationConfigBuilder().build())

        XCTAssertTrue(manager.centralConfigManager is OpampCentralConfigManager)
        XCTAssertFalse(manager.isRegistered(server.baseURL.appendingPathComponent("config/v1/agents")))
        XCTAssertTrue(manager.isRegistered(server.baseURL.appendingPathComponent("opamp")))
        XCTAssertEqual(manager.registeredEndpointCount, 1)
      }
    }
  #endif
}
