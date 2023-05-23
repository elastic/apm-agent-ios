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

class SessionSampler: NSObject {
  private let accessQueue = DispatchQueue(
    label: "SessionSampler.accessor", qos: .default, attributes: .concurrent)

  private let sampleRateResolver: () -> Double

  private var _shouldSample: Bool = true

  public private(set) var shouldSample: Bool {
    get {
      var shouldSample = true
      accessQueue.sync {
        shouldSample = _shouldSample
      }
      return shouldSample
    }
    set {
      accessQueue.async(flags: .barrier) {
        self._shouldSample = newValue
      }
    }
  }

  init(_ sampleRateResolver: @escaping () -> Double = { return CentralConfig().data.sampleRate }) {
    self.sampleRateResolver = sampleRateResolver

    super.init()
    NotificationCenter.default.addObserver(
      self, selector: #selector(handleSessionChange), name: .ElasticSessionManagerDidRefreshSession,
      object: nil)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  @objc
  func handleSessionChange(_ notification: NSNotification) {
    let sampleRate = sampleRateResolver()
    shouldSample = Double.random(in: 0...1) <= sampleRate
  }
}
