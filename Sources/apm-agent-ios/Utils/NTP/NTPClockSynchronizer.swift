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

import Darwin
import Foundation
import os.log

/// Owns the process-wide network time anchor that span and log timestamps read.
///
/// One SNTP attempt sets an anchor: the synchronized time and the continuous-clock value at
/// the reply. Reads extrapolate from the anchor with the continuous clock, which advances during
/// sleep and ignores wall-clock changes. Without an anchor, reads use the wall clock.
final class NTPClockSynchronizer {
  struct Anchor: Equatable {
    let unixNanos: Int64
    let continuousNanos: UInt64
  }

  #if os(watchOS)
  static let shared = NTPClockSynchronizer(transport: nil)
  #else
  static let shared = NTPClockSynchronizer(transport: SNTPUDPTransport())
  #endif

  private static let logger = OSLog(subsystem: "co.elastic.ElasticApm", category: "NTPClock")
  private static let deadlineNanos = UInt64(SNTPAttempt.deadline * 1e9)

  private let transport: SNTPTransport?
  private let continuousClock: () -> UInt64
  private let wallClock: () -> Date
  private let lock = NSLock()
  // Guarded by `lock`.
  private var currentAnchor: Anchor?
  private var attemptInFlight = false

  init(
    transport: SNTPTransport?,
    continuousClock: @escaping () -> UInt64 = ContinuousTime.nanoseconds,
    wallClock: @escaping () -> Date = Date.init
  ) {
    self.transport = transport
    self.continuousClock = continuousClock
    self.wallClock = wallClock
  }

  var anchor: Anchor? {
    lock.lock()
    defer { lock.unlock() }
    return currentAnchor
  }

  var now: Date {
    guard let anchor else {
      return wallClock()
    }
    let elapsed = Int64(bitPattern: continuousClock() &- anchor.continuousNanos)
    return Date(timeIntervalSince1970: Double(anchor.unixNanos + elapsed) / 1e9)
  }

  /// Starts one SNTP attempt unless one is already in flight. Never blocks on the network.
  func synchronize() {
    guard let transport else {
      return
    }
    lock.lock()
    guard !attemptInFlight else {
      lock.unlock()
      return
    }
    attemptInFlight = true
    lock.unlock()

    // The transport builds the request when it sends it, so the references exclude name
    // resolution and connection setup. It calls the builder before the completion.
    var sent: SentRequest?
    transport.exchange(
      { [self] in
        let request = SentRequest(
          unixNanos: Int64((wallClock().timeIntervalSince1970 * 1e9).rounded()),
          continuousNanos: continuousClock())
        sent = request
        return request.packet.encoded()
      },
      completion: { [self] result in
        finishAttempt(result.flatMap { makeAnchor(reply: $0, request: sent) })
      })
  }

  /// Validates a reply against the request references and derives the anchor.
  private func makeAnchor(reply: Data, request: SentRequest?) -> Result<Anchor, SNTPFailure> {
    let replyContinuous = continuousClock()
    guard let request else {
      return .failure(.connectionFailed)
    }
    let elapsed = replyContinuous &- request.continuousNanos
    guard elapsed <= Self.deadlineNanos else {
      return .failure(.timeout)
    }
    // Measure the reply time from the request's wall-clock reference so that a wall-clock
    // change during the exchange cannot shift it.
    let replyUnixNanos = request.unixNanos + Int64(elapsed)
    return SNTPPacket.offset(
      request: request.packet,
      reply: reply,
      receiveTime: SNTPPacket.ntpTime(unixNanos: replyUnixNanos)
    ).map {
      Anchor(unixNanos: replyUnixNanos + $0, continuousNanos: replyContinuous)
    }
  }

  private func finishAttempt(_ result: Result<Anchor, SNTPFailure>) {
    lock.lock()
    if case let .success(anchor) = result {
      currentAnchor = anchor
    }
    attemptInFlight = false
    lock.unlock()

    switch result {
    case .success:
      os_log("Network time synchronized for signal timestamps.", log: Self.logger, type: .info)
    case let .failure(failure):
      os_log(
        "Network time synchronization failed (%{public}@); signal timestamps keep their current source.",
        log: Self.logger,
        type: .info,
        String(describing: failure))
    }
  }
}

/// The send-time references of one SNTP request.
private struct SentRequest {
  let unixNanos: Int64
  let continuousNanos: UInt64

  var packet: SNTPPacket {
    SNTPPacket(transmitTime: SNTPPacket.ntpTime(unixNanos: unixNanos))
  }
}

/// `mach_continuous_time()` in nanoseconds. It advances during sleep and is unaffected by
/// wall-clock changes.
enum ContinuousTime {
  private static let timebase: mach_timebase_info_data_t = {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return info
  }()

  static func nanoseconds() -> UInt64 {
    let ticks = mach_continuous_time()
    let product = ticks.multipliedFullWidth(by: UInt64(timebase.numer))
    return UInt64(timebase.denom).dividingFullWidth(product).quotient
  }
}
