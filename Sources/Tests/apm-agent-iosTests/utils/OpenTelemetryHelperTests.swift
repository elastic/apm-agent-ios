//
//  Copyright © 2025  Elasticsearch BV
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
import OpenTelemetrySdk
@testable import ElasticApm

class OpenTelemetryHelperTests : XCTestCase {
  func testGetURL() {
    let simpleHttp = URL(string:"http://localhost")!
    XCTAssertEqual(
      simpleHttp,
      OpenTelemetryHelper.getURL(with: AgentConfigBuilder().withExportUrl(simpleHttp).build())
    )
    let portHttp = URL(string: "http://localhost:8200")!
    XCTAssertEqual(
      portHttp,
      OpenTelemetryHelper.getURL(with: AgentConfigBuilder().withExportUrl(portHttp).build())
    )

    let pathHttp = URL(string: "http://localhost/unique/path")!
    XCTAssertEqual(
      pathHttp,
      OpenTelemetryHelper.getURL(with: AgentConfigBuilder().withExportUrl(pathHttp).build())
    )

    let portPathHttp = URL(string: "http://localhost:8200/unique/path")!
    XCTAssertEqual(
      portPathHttp,
      OpenTelemetryHelper.getURL(with: AgentConfigBuilder().withExportUrl(portPathHttp).build())
    )

    let portPathHttps = URL(string: "https://localhost:8200/unique/path")!
    XCTAssertEqual(
      portPathHttps,
      OpenTelemetryHelper.getURL(with: AgentConfigBuilder().withExportUrl(portPathHttps).build())
    )

    let defaultPortHttps = URL(string: "https://localhost:443/unique/path")!
    XCTAssertEqual(
      URL(string: "https://localhost/unique/path")!,
      OpenTelemetryHelper.getURL(with: AgentConfigBuilder().withExportUrl(defaultPortHttps).build())
    )

    let defaultExportUrl = URL(string: "http://127.0.0.1:8200")
    XCTAssertEqual(
      defaultExportUrl,
      OpenTelemetryHelper.getURL(with: AgentConfigBuilder().build())
    )

  }
}
