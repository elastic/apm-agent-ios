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

import OpenTelemetryApi
import OpenTelemetrySdk
import XCTest

@testable import ElasticApm

final class TransactionHelperTests: XCTestCase {
  func testHTTPSpanDetectionAcceptsStableAndLegacyURLKeys() throws {
    XCTAssertTrue(try makeSpan(attributeName: "url.full").isHttpSpan())
    XCTAssertTrue(try makeSpan(attributeName: "http.url").isHttpSpan())
    XCTAssertFalse(try makeSpan(attributeName: "url.path").isHttpSpan())
  }

  private func makeSpan(attributeName: String) throws -> any ReadableSpan {
    let tracer = TracerProviderBuilder()
      .build()
      .get(instrumentationName: "TransactionHelperTests")
    let span = tracer.spanBuilder(spanName: "test-span")
      .setAttribute(key: attributeName, value: .string("https://example.com"))
      .startSpan()
    return try XCTUnwrap(span as? any ReadableSpan)
  }
}
