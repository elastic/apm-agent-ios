// Copyright © 2025  Elasticsearch BV
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

final class OpenTelemetryHelperTests: XCTestCase {
  func testUsesTheCanonicalFullURL() {
    let endpoints = [
      URL(string: "http://collector.example.com")!,
      URL(string: "http://collector.example.com:4318/unique/path")!,
      URL(string: "https://collector.example.com:8443/unique/path")!
    ]

    for endpoint in endpoints {
      let configuration = AgentConfigBuilder().withExportUrl(endpoint).build()
      XCTAssertEqual(OpenTelemetryHelper.getURL(with: configuration), endpoint)
    }
  }

  func testDoesNotActivateUntouchedCompatibilityDefaults() {
    XCTAssertNil(OpenTelemetryHelper.getURL(with: AgentConfigBuilder().build()))
  }

  func testChannelTargetUsesTheCanonicalEndpoint() {
    let endpoints = [
      (
        URL(string: "http://collector.example.com:4318")!,
        GrpcChannelTarget(host: "collector.example.com", port: 4318, useTLS: false)
      ),
      (
        URL(string: "https://collector.example.com:8443")!,
        GrpcChannelTarget(host: "collector.example.com", port: 8443, useTLS: true)
      ),
      (
        URL(string: "https://collector.example.com")!,
        GrpcChannelTarget(host: "collector.example.com", port: 443, useTLS: true)
      )
    ]

    for (endpoint, expectedTarget) in endpoints {
      let configuration = AgentConfigBuilder()
        .withExportUrl(endpoint)
        .useConnectionType(.grpc)
        .build()
      XCTAssertEqual(OpenTelemetryHelper.channelTarget(with: configuration), expectedTarget)
    }
  }

  func testChannelTargetIgnoresDeprecatedMutationsAfterAFullURL() {
    var configuration = AgentConfigBuilder()
      .withExportUrl(URL(string: "https://canonical.example.com:8443")!)
      .useConnectionType(.grpc)
      .build()
    configuration.collectorHost = "ignored.example.com"
    configuration.collectorPort = 4317
    configuration.collectorTLS = false

    XCTAssertEqual(
      OpenTelemetryHelper.channelTarget(with: configuration),
      GrpcChannelTarget(host: "canonical.example.com", port: 8443, useTLS: true)
    )
  }
}
