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

#if !os(watchOS) // Crash reporting is not supported on watchOS.
  import XCTest

  @testable import ElasticApm

  final class CrashManagerTests: XCTestCase {
    func testDefaultCrashEventUsesCurrentName() {
      XCTAssertEqual(
        CrashManager.eventName(useLegacyAttributeNames: false),
        "app.crash"
      )
      XCTAssertNotEqual(
        CrashManager.eventName(useLegacyAttributeNames: false),
        "crash"
      )
    }

    func testLegacyCrashEventRestoresPreviousName() {
      XCTAssertEqual(
        CrashManager.eventName(useLegacyAttributeNames: true),
        "crash"
      )
      XCTAssertNotEqual(
        CrashManager.eventName(useLegacyAttributeNames: true),
        "app.crash"
      )
    }
  }
#else
  import XCTest

  final class CrashManagerTests: XCTestCase {
    func testUnsupportedPlatformReportsSkip() throws {
      throw XCTSkip("Crash reporting is not supported on watchOS.")
    }
  }
#endif
