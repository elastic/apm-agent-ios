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

protocol RequestTimer {
  func setEventHandler(_ handler: @escaping () -> Void)
  /// Schedules the next fire after `delay`. A `nil` `repeating` schedules a one-shot timer.
  func schedule(delay: TimeInterval, repeating: TimeInterval?)
  func activate()
  func cancel()
}

class DispatchSourceRequestTimer: RequestTimer {
  private let timer: DispatchSourceTimer

  init(
    queue: DispatchQueue = DispatchQueue(
      label: "com.elastic.apm.agent.opamp.http.request.timer",
      qos: .utility)
  ) {
    self.timer = DispatchSource.makeTimerSource(queue: queue)
  }

  func setEventHandler(_ handler: @escaping () -> Void) {
    timer.setEventHandler(handler: handler)
  }

  func schedule(delay: TimeInterval, repeating: TimeInterval?) {
    if let repeating = repeating {
      timer.schedule(deadline: .now() + delay, repeating: repeating)
    } else {
      timer.schedule(deadline: .now() + delay, repeating: .never)
    }
  }

  func activate() {
    timer.activate()
  }

  func cancel() {
    timer.cancel()
  }
}
