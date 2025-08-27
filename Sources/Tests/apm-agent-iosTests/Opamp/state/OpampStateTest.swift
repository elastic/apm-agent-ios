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
@testable import ElasticApm

class OpampStateTest: XCTestCase {
  func testMutex() {
    let state = OpampState<Int>(0)
    DispatchQueue.concurrentPerform(iterations: 1000, execute: { _ in
      state.value += 1
    })
    XCTAssertTrue(state == 1000)
  }

  func testNotify() {

    class StateNotification : OpampState<Int>, @unchecked Sendable {
      var expectation : XCTestExpectation?
      override func notify() {
        expectation!.fulfill()
      }
    }

    let expectation = expectation(description: "notify")

    let state = StateNotification(0)
    state.expectation = expectation

    state.value += 1
    waitForExpectations(timeout: 0) // state calls notify on state change
  }

  func testStateAsSupplier() {
    let state = OpampState<Int>(0)
    state.value += 1
    XCTAssertEqual(1, state.get())
  }
}
