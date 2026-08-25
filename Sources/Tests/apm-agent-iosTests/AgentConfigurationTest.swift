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

final class AgentConfigurationTest: XCTestCase {
  func testBuildWithoutAnEndpointIsNonThrowingAndReportsTheStableDiagnostic() {
    let configuration: AgentConfiguration = AgentConfigBuilder().build()

    let resolution = configuration.resolveExportEndpoint()
    XCTAssertNil(resolution.url)
    XCTAssertNil(resolution.warning)
    XCTAssertEqual(
      resolution.validationMessage,
      AgentConfiguration.exportEndpointValidationMessage
    )
  }

  func testInvalidEndpointsReportTheStableDiagnostic() {
    let invalidUrls = [
      URL(string: "relative/path")!,
      URL(string: "ftp://collector.example.com")!,
      URL(string: "https:///v1/traces")!,
      URL(string: "https://collector.example.com:0")!,
      URL(string: "https://collector.example.com:65536")!
    ]

    for invalidUrl in invalidUrls {
      let resolution = AgentConfigBuilder()
        .withExportUrl(invalidUrl)
        .build()
        .resolveExportEndpoint()
      XCTAssertNil(resolution.url, "\(invalidUrl) must be rejected")
      XCTAssertEqual(
        resolution.validationMessage,
        AgentConfiguration.exportEndpointValidationMessage
      )
    }
  }

  func testValidURLsPreservePathAndPortAndDeriveTLSFromScheme() {
    let http = URL(string: "http://collector.example.com:4318/otlp")!
    let https = URL(string: "https://collector.example.com:8443/otlp")!

    let httpConfiguration = AgentConfigBuilder().withExportUrl(http).build()
    XCTAssertEqual(httpConfiguration.resolveExportEndpoint().url, http)
    XCTAssertEqual(OpenTelemetryHelper.getURL(with: httpConfiguration), http)
    XCTAssertFalse(httpConfiguration.collectorTLS)
    XCTAssertEqual(httpConfiguration.collectorPort, 4318)
    XCTAssertEqual(httpConfiguration.collectorPath, "/otlp")

    let httpsConfiguration = AgentConfigBuilder().withExportUrl(https).build()
    XCTAssertEqual(httpsConfiguration.resolveExportEndpoint().url, https)
    XCTAssertEqual(OpenTelemetryHelper.getURL(with: httpsConfiguration), https)
    XCTAssertTrue(httpsConfiguration.collectorTLS)
    XCTAssertEqual(httpsConfiguration.collectorPort, 8443)
    XCTAssertEqual(httpsConfiguration.collectorPath, "/otlp")
  }

  func testOmittedPortsAreDerivedFromTheURLScheme() {
    let http = AgentConfigBuilder()
      .withExportUrl(URL(string: "http://collector.example.com")!)
      .build()
    let https = AgentConfigBuilder()
      .withExportUrl(URL(string: "https://collector.example.com")!)
      .build()

    XCTAssertEqual(http.collectorPort, 80)
    XCTAssertFalse(http.collectorTLS)
    XCTAssertEqual(https.collectorPort, 443)
    XCTAssertTrue(https.collectorTLS)
  }

  func testHTTPIsTheDefaultConnectionTypeAndGrpcRemainsAnOptIn() {
    XCTAssertEqual(AgentConfigBuilder().build().connectionType, .http)
    XCTAssertEqual(
      AgentConfigBuilder().useConnectionType(.grpc).build().connectionType,
      .grpc
    )
  }

  func testLegacyAttributeNamesAreDisabledByDefaultAndCanBeSelectedExplicitly() {
    XCTAssertFalse(AgentConfigBuilder().build().useLegacyAttributeNames)
    XCTAssertTrue(
      AgentConfigBuilder()
        .useLegacyAttributeNames(true)
        .build()
        .useLegacyAttributeNames
    )
    XCTAssertFalse(
      AgentConfigBuilder()
        .useLegacyAttributeNames(true)
        .useLegacyAttributeNames(false)
        .build()
        .useLegacyAttributeNames
    )
  }

  func testDeprecatedServerURLRemainsCompatibleAndExportURLTakesPrecedence() {
    let serverUrl = URL(string: "http://legacy.example.com:4317")!
    let exportUrl = URL(string: "https://export.example.com:4318/v1")!

    let serverOnly = AgentConfigBuilder().withServerUrl(serverUrl).build()
    XCTAssertEqual(serverOnly.resolveExportEndpoint().url, serverUrl)

    let configuration = AgentConfigBuilder()
      .withServerUrl(serverUrl)
      .withExportUrl(exportUrl)
      .build()
    XCTAssertEqual(configuration.resolveExportEndpoint().url, exportUrl)
    XCTAssertEqual(
      configuration.managementUrlComponents().url,
      URL(string: "https://export.example.com:4318/v1/config/v1/agents")
    )
  }

  func testManagementURLDoesNotDuplicateTrailingPathSeparator() {
    let configuration = AgentConfigBuilder()
      .withExportUrl(URL(string: "https://export.example.com:4318/otlp/")!)
      .build()

    XCTAssertEqual(
      configuration.managementUrlComponents().url,
      URL(string: "https://export.example.com:4318/otlp/config/v1/agents")
    )
  }

  func testDeprecatedEndpointPropertiesRemainAssignableAndAdaptLiveValues() {
    var configuration = AgentConfigBuilder().build()
    configuration.collectorHost = "legacy.example.com"
    configuration.collectorPath = "/ingest"
    configuration.collectorPort = 4318
    configuration.collectorTLS = true

    let resolution = configuration.resolveExportEndpoint()
    XCTAssertEqual(
      resolution.url,
      URL(string: "https://legacy.example.com:4318/ingest")
    )
    XCTAssertEqual(
      resolution.warning,
      AgentConfiguration.deprecatedEndpointMigrationWarning
    )
    XCTAssertNil(resolution.validationMessage)
  }

  func testPartialDeprecatedEndpointChangesUseTheCompatibilityDefaults() {
    var configuration = AgentConfigBuilder().build()
    configuration.collectorPath = "/ingest"

    let resolution = configuration.resolveExportEndpoint()
    XCTAssertEqual(
      resolution.url,
      URL(string: "http://127.0.0.1:8200/ingest")
    )
    XCTAssertEqual(
      resolution.warning,
      AgentConfiguration.deprecatedEndpointMigrationWarning
    )
  }

  func testFullURLProjectionIsNotTreatedAsDeprecatedPropertyMutation() {
    let exportUrl = URL(string: "https://collector.example.com:8443/otlp")!
    let configuration = AgentConfigBuilder().withExportUrl(exportUrl).build()

    let resolution = configuration.resolveExportEndpoint()
    XCTAssertEqual(resolution.url, exportUrl)
    XCTAssertNil(resolution.warning)
  }

  func testFullURLWinsAfterDeprecatedEndpointPropertyMutation() {
    let exportUrl = URL(string: "https://collector.example.com:8443/otlp")!
    var configuration = AgentConfigBuilder()
      .withExportUrl(exportUrl)
      .useConnectionType(.grpc)
      .build()
    configuration.collectorHost = "ignored.example.com"
    configuration.collectorPath = "/ignored"
    configuration.collectorPort = 4317
    configuration.collectorTLS = false

    let resolution = configuration.resolveExportEndpoint()
    XCTAssertEqual(resolution.url, exportUrl)
    XCTAssertEqual(configuration.connectionType, .grpc)
    XCTAssertEqual(
      resolution.warning,
      AgentConfiguration.ignoredDeprecatedEndpointMutationWarning
    )
    XCTAssertEqual(OpenTelemetryHelper.getURL(with: configuration), exportUrl)
    XCTAssertEqual(
      configuration.managementUrlComponents().url,
      URL(string: "https://collector.example.com:8443/otlp/config/v1/agents")
    )
  }

  func testInvalidFullURLDoesNotFallBackToDeprecatedEndpointProperties() {
    var configuration = AgentConfigBuilder()
      .withExportUrl(URL(string: "ftp://collector.example.com")!)
      .build()
    configuration.collectorHost = "legacy.example.com"
    configuration.collectorPort = 4318

    let resolution = configuration.resolveExportEndpoint()
    XCTAssertNil(resolution.url)
    XCTAssertEqual(
      resolution.warning,
      AgentConfiguration.ignoredDeprecatedEndpointMutationWarning
    )
    XCTAssertEqual(
      resolution.validationMessage,
      AgentConfiguration.exportEndpointValidationMessage
    )
  }
}
