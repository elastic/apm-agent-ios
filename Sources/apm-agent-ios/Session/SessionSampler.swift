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
import OpenTelemetryApi
@_implementationOnly import OpenTelemetrySdk

class SessionSampler: NSObject, Sampler {

  private struct SimpleDecision: Decision {
    let decision: Bool

    /// Creates sampling decision without attributes.
    /// - Parameter decision: sampling decision
    init(decision: Bool) {
      self.decision = decision
    }

    public var isSampled: Bool {
      return decision
    }

    public var attributes: [String: AttributeValue] {
      return [String: AttributeValue]()
    }
  }

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

  private override init() {
    self.sampleRateResolver = { return 1.0 }
    super.init()
  }

  init(_ sampleRateResolver: @escaping () -> Double) {
    self.sampleRateResolver = sampleRateResolver

    super.init()
    NotificationCenter.default.addObserver(
      self, selector: #selector(handleSessionChange), name: .elasticSessionManagerDidRefreshSession,
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
  // swiftlint:disable:next function_parameter_count
  func shouldSample(
    parentContext: SpanContext?,
    traceId: TraceId,
    name: String,
    kind: SpanKind,
    attributes: [String: AttributeValue],
    parentLinks: [SpanData.Link]
  ) -> Decision {
    return SimpleDecision(decision: shouldSample)

  }
}
