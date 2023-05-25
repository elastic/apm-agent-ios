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

@testable import iOSAgent

final class SessionSamplerTests: XCTestCase {

  func testSampleRate() {
    let sampler = SessionSampler {
      return 0.5
    }
    var count = 0
    for _ in 0...10000 {
      sampler.handleSessionChange(
        NSNotification(name: .elasticSessionManagerDidRefreshSession, object: self))
      if sampler.shouldSample {
        count += 1
      }
    }
    XCTAssertEqual(0.5 - (Double(count) / 10000.0), 0, accuracy: 0.01)
  }

  func testLowSampleRate() {
    let sampler = SessionSampler {
      return 0.01
    }
    var count = 0
    for _ in 0...10000 {
      sampler.handleSessionChange(
        NSNotification(name: .elasticSessionManagerDidRefreshSession, object: self))
      if sampler.shouldSample {
        count += 1
      }
    }
    XCTAssertEqual(0.01 - (Double(count) / 10000.0), 0, accuracy: 0.01)
  }
}
