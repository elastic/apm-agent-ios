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
    let multiInterceptor = MultiInterceptor<String>(
      [AnyInterceptor(NoopInterceptor<String>()), AnyInterceptor(NoopInterceptor<String>())]
    )
    XCTAssert(multiInterceptor.interceptors.count == 0)
  }

  func testNoNestedMultiInterceptors() {
    let myInterceptor = ClosureInterceptor<String> { s in return "true" }
    let nestedMultiInterceptor = MultiInterceptor<String>(
      [
        AnyInterceptor(NoopInterceptor<String>()),
        AnyInterceptor(MultiInterceptor<String>([AnyInterceptor(myInterceptor)])),
      ]
    )
    XCTAssert(nestedMultiInterceptor.interceptors.count == 1)
    XCTAssertFalse(
      nestedMultiInterceptor.interceptors[0].base is MultiInterceptor<String>
    )
    XCTAssertEqual(nestedMultiInterceptor.intercept(""), "true")
  }

  func testNestedMultiInterceptorRunsAtItsPosition() {
    let a = ClosureInterceptor<String> { s in return s + "a" }
    let b = ClosureInterceptor<String> { s in return s + "b" }
    let c = ClosureInterceptor<String> { s in return s + "c" }
    let d = ClosureInterceptor<String> { s in return s + "d" }
    let multiInterceptor = MultiInterceptor<String>(
      [
        AnyInterceptor(a),
        AnyInterceptor(MultiInterceptor<String>([AnyInterceptor(b), AnyInterceptor(c)])),
        AnyInterceptor(d),
      ]
    )
    XCTAssertEqual(multiInterceptor.intercept(""), "abcd")
    XCTAssertEqual(multiInterceptor.interceptors.count, 4)
  }

  func testExistentialArrayInitializerMatchesTypeErasedInitializer() throws {
    guard #available(iOS 16, tvOS 16, watchOS 9, *) else {
      throw XCTSkip("The [any Interceptor<T>] initializer requires iOS 16, tvOS 16, or watchOS 9.")
    }
    let a = ClosureInterceptor<String> { s in return s + "a" }
    let b = ClosureInterceptor<String> { s in return s + "b" }
    let interceptors: [any Interceptor<String>] = [
      a, NoopInterceptor<String>(), MultiInterceptor<String>([AnyInterceptor(b)]),
    ]
    let multiInterceptor = MultiInterceptor<String>(interceptors)
    XCTAssertEqual(multiInterceptor.intercept(""), "ab")
    XCTAssertEqual(multiInterceptor.interceptors.count, 2)
  }

  func testSeveralInterceptors() {
    let interceptors = ClosureInterceptor<String> {s in return s + " hello" }
      .join { s in
        return s + ", world"
      }
    XCTAssertEqual(interceptors.intercept("well,"), "well, hello, world")

  }
}

