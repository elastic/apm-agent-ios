//
//  Copyright © 2026  Elasticsearch BV
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
@testable import ElasticApm

/// Deterministic RequestTimer for tests: records every schedule and only
/// fires when the test calls `fire()`, so no assertions depend on wall-clock time.
class MockRequestTimer: RequestTimer {

  struct Schedule: Equatable {
    let delay: TimeInterval
    let repeating: TimeInterval?
  }

  private var handler: (() -> Void)?
  private(set) var schedules = [Schedule]()
  private(set) var isActivated = false
  private(set) var isCancelled = false

  var lastSchedule: Schedule? { schedules.last }

  func setEventHandler(_ handler: @escaping () -> Void) {
    self.handler = handler
  }

  func schedule(delay: TimeInterval, repeating: TimeInterval?) {
    // a real DispatchSourceTimer ignores schedules after cancellation
    if isCancelled {
      return
    }
    schedules.append(Schedule(delay: delay, repeating: repeating))
  }

  func activate() {
    isActivated = true
  }

  func cancel() {
    isCancelled = true
  }

  /// Simulates the timer firing, like a DispatchSourceTimer reaching its deadline.
  func fire() {
    guard isActivated, !isCancelled else {
      return
    }
    handler?()
  }
}
