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
import os.log
#if !os(watchOS)
import Kronos
#endif

class SuccessLogOnce {
  static let run: Void = {
    let logger  = OSLog(subsystem: "co.elastic.ElasticApm", category: "NTPClock")
    os_log("NTPClock is now being used for signal timestamps.", log: logger, type: .info)
    return ()
  }()
}

class FailureLogOnce {
  static let run: Void = {
    let logger  = OSLog(subsystem: "co.elastic.ElasticApm", category: "NTPClock")
    os_log("NTPClock is unavailable. Using system clock as fallback for signal timestamps.", log: logger, type: .info)
    return()
  }()
}

class NTPClock: OpenTelemetrySdk.Clock {
  var now: Date {
    #if !os(watchOS)
    if let date = Kronos.Clock.now {
      SuccessLogOnce.run
      return date
    }
    FailureLogOnce.run
    #endif
    return Date()
  }
}
