// Copyright © 2025 Elasticsearch BV
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
class InterceptorTests : XCTestCase {
  func testNoNoopInMultiInterceptors() {
    let multiInterceptor = MultiInterceptor<String>([NoopInterceptor<String>(), NoopInterceptor<String>()])
    XCTAssert(multiInterceptor.interceptors.count == 0)
  }

  func testNoNestedMultiInterceptors() {
    let myInterceptor = ClosureInterceptor<String> { s in return "true" }
    let nestedMultiInterceptor = MultiInterceptor<String>(
      [NoopInterceptor<String>(), MultiInterceptor<String>([myInterceptor])]
    )
    XCTAssert(nestedMultiInterceptor.interceptors.count == 1)
    XCTAssertFalse(
      nestedMultiInterceptor.interceptors[0] is MultiInterceptor<String>
    )
    XCTAssertEqual(nestedMultiInterceptor.intercept(""), "true")
  }

  func testSeveralInterceptors() {
    let interceptors = ClosureInterceptor<String> {s in return s + " hello" }
      .join { s in
        return s + ", world"
      }
    XCTAssertEqual(interceptors.intercept("well,"), "well, hello, world")

  }
}

