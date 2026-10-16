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
///
/// Each anchor is saved, and `start()` restores it in a later launch of the same boot. The anchor's
/// age is measured on the continuous clock: at 1 hour a new attempt starts, at 24 hours the anchor
/// is discarded. A tick checks the age every minute while the process runs, which also retries
/// once a minute until the first attempt succeeds.
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
  private static let refreshAgeNanos: UInt64 = 3_600 * 1_000_000_000
  private static let maxAgeNanos: UInt64 = 24 * refreshAgeNanos
  private static let bootTimeToleranceNanos: UInt64 = 1_000_000_000

  private let transport: SNTPTransport?
  private let store: NTPAnchorStore
  private let tick: RepeatingTick
  private let continuousClock: () -> UInt64
  private let wallClock: () -> Date
  private let lock = NSLock()
  // Storage writes run here, never while `lock` is held: `UserDefaults` notifies its observers
  // synchronously on the writing thread, and an observer may read the clock.
  private let storageQueue = DispatchQueue(label: "co.elastic.ntp.storage")
  // Guarded by `lock`.
  private var currentAnchor: Anchor?
  private var attemptInFlight = false
  private var started = false

  init(
    transport: SNTPTransport?,
    userDefaults: UserDefaults = .standard,
    tick: RepeatingTick = DispatchRepeatingTick(interval: .seconds(60), leeway: .seconds(10)),
    continuousClock: @escaping () -> UInt64 = ContinuousTime.nanoseconds,
    wallClock: @escaping () -> Date = Date.init
  ) {
    self.transport = transport
    self.store = NTPAnchorStore(userDefaults: userDefaults)
    self.tick = tick
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

  /// Restores the saved anchor, starts an attempt when it is missing or stale, and starts the age
  /// check tick. Runs once, and does nothing without a transport.
  func start() {
    guard transport != nil else {
      return
    }
    lock.lock()
    guard !started else {
      lock.unlock()
      return
    }
    started = true
    let rejection = restoreSavedAnchor()
    lock.unlock()

    if let rejection {
      os_log(
        "Saved network time not restored (%{public}@).",
        log: Self.logger,
        type: .info,
        String(describing: rejection))
    } else {
      os_log("Saved network time restored for signal timestamps.", log: Self.logger, type: .info)
    }
    refreshIfDue()
    tick.start { [weak self] in self?.refreshIfDue() }
  }

  /// Discards an anchor that is 24 hours or older, then starts an attempt when there is no anchor
  /// or it is 1 hour or older.
  private func refreshIfDue() {
    lock.lock()
    let continuous = continuousClock()
    var expired = false
    if let anchor = currentAnchor, continuous &- anchor.continuousNanos >= Self.maxAgeNanos {
      currentAnchor = nil
      persist { $0.remove() }
      expired = true
    }
    let due = currentAnchor.map { continuous &- $0.continuousNanos >= Self.refreshAgeNanos } ?? true
    lock.unlock()

    if expired {
      os_log(
        "Network time expired; signal timestamps use the system clock.", log: Self.logger, type: .info)
    }
    if due {
      synchronize()
    }
  }

  /// Installs the saved anchor when it was saved in this boot less than 24 hours ago. Otherwise
  /// removes it and returns the reason. Requires `lock`.
  private func restoreSavedAnchor() -> RestoreRejection? {
    let saved: NTPAnchorStore.Saved
    switch store.load() {
    case .absent:
      return .absent
    case .malformed:
      persist { $0.remove() }
      return .malformed
    case let .saved(value):
      saved = value
    }
    let continuous = continuousClock()
    let bootShift = bootNanos(continuous: continuous).subtractingReportingOverflow(saved.bootNanos)
    let rejection: RestoreRejection
    if saved.anchor.continuousNanos > continuous || bootShift.overflow
      || bootShift.partialValue.magnitude > Self.bootTimeToleranceNanos {
      rejection = .rebooted
    } else if continuous - saved.anchor.continuousNanos >= Self.maxAgeNanos {
      rejection = .expired
    } else {
      currentAnchor = saved.anchor
      return nil
    }
    persist { $0.remove() }
    return rejection
  }

  /// Queues a storage write. Writes run in the order they are queued.
  private func persist(_ write: @escaping (NTPAnchorStore) -> Void) {
    storageQueue.async { [store] in write(store) }
  }

  /// The boot time derived from the wall clock and `continuous`. The wall clock is used only here,
  /// to detect a reboot.
  private func bootNanos(continuous: UInt64) -> Int64 {
    Int64((wallClock().timeIntervalSince1970 * 1e9).rounded()) &- Int64(bitPattern: continuous)
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
      let saved = NTPAnchorStore.Saved(
        anchor: anchor, bootNanos: bootNanos(continuous: continuousClock()))
      persist { $0.save(saved) }
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

private enum RestoreRejection {
  case absent
  case malformed
  case rebooted
  case expired
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
