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

import Foundation

/// Calls a handler repeatedly until the process ends.
protocol RepeatingTick: AnyObject {
  /// Starts calling `handler` on a background queue. Call it at most once.
  func start(_ handler: @escaping () -> Void)
}

/// A dispatch timer on its own background queue. Dispatch timers do not advance while the device
/// sleeps, so the handler must check elapsed time itself instead of counting ticks.
final class DispatchRepeatingTick: RepeatingTick {
  private let interval: DispatchTimeInterval
  private let leeway: DispatchTimeInterval
  private let queue = DispatchQueue(label: "co.elastic.ntp.tick", qos: .utility)
  private var timer: DispatchSourceTimer?

  init(interval: DispatchTimeInterval, leeway: DispatchTimeInterval) {
    self.interval = interval
    self.leeway = leeway
  }

  func start(_ handler: @escaping () -> Void) {
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + interval, repeating: interval, leeway: leeway)
    timer.setEventHandler(handler: handler)
    timer.resume()
    self.timer = timer
  }
}
