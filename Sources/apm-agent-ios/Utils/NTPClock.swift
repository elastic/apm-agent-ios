// Copyright © 2022 Elasticsearch BV
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
import OpenTelemetrySdk

/// The span and log clock. It reads the process-wide network time anchor.
class NTPClock: OpenTelemetrySdk.Clock {
  private let synchronizer: NTPClockSynchronizer

  init(synchronizer: NTPClockSynchronizer = .shared) {
    self.synchronizer = synchronizer
  }

  var now: Date {
    synchronizer.now
  }
}
