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
import XCTest

@testable import ElasticApm

let nanosPerSecond: Int64 = 1_000_000_000

/// Builds a server reply to `request`. By default it is valid, and the server clock reads
/// `serverAhead` later than the request's transmit time when it receives and sends.
func sntpReply(
  to request: Data,
  serverAhead: Int64,
  leapIndicator: UInt8 = 0,
  version: UInt8 = 4,
  mode: UInt8 = 4,
  stratum: UInt8 = 1,
  originateTime: Int64? = nil,
  transmitTime: Int64? = nil
) -> Data {
  let requestTime = SNTPPacket(parsing: request)!.transmitTime
  let serverTime = requestTime + serverAhead
  return SNTPPacket(
    leapIndicator: leapIndicator,
    version: version,
    mode: mode,
    stratum: stratum,
    originateTime: originateTime ?? requestTime,
    receiveTime: serverTime,
    transmitTime: transmitTime ?? serverTime
  ).encoded()
}

/// Each class of reply that the client must reject, keyed by the expected failure.
func rejectedSNTPReplies(to request: Data) -> [(SNTPFailure, Data)] {
  let valid = { (leap: UInt8, version: UInt8, mode: UInt8, stratum: UInt8) in
    sntpReply(
      to: request, serverAhead: 30 * nanosPerSecond, leapIndicator: leap, version: version,
      mode: mode, stratum: stratum)
  }
  let requestTime = SNTPPacket(parsing: request)!.transmitTime
  return [
    (.replyTooShort, valid(0, 4, 4, 1).prefix(47)),
    (
      .originateTimeMismatch,
      sntpReply(to: request, serverAhead: 0, originateTime: requestTime + nanosPerSecond)
    ),
    (.serverUnsynchronized, valid(3, 4, 4, 1)),
    (.serverUnsynchronized, valid(0, 4, 4, 0)),
    (.serverUnsynchronized, valid(0, 4, 4, 16)),
    (.serverUnsynchronized, valid(0, 4, 4, 200)),
    (.invalidVersion, valid(0, 3, 4, 1)),
    (.invalidMode, valid(0, 4, 3, 1)),
    (.invalidTransmitTime, sntpReply(to: request, serverAhead: 0, transmitTime: 0))
  ]
}

/// A continuous clock that tests advance by hand.
final class ManualContinuousClock {
  private let lock = NSLock()
  private var nanos: UInt64

  init(nanos: UInt64 = 1_000 * UInt64(nanosPerSecond)) {
    self.nanos = nanos
  }

  func read() -> UInt64 {
    lock.lock()
    defer { lock.unlock() }
    return nanos
  }

  func advance(by delta: Int64) {
    lock.lock()
    nanos += UInt64(delta)
    lock.unlock()
  }
}

/// A transport that answers each request through `reply`, or holds it when `reply` returns `nil`.
/// `beforeRequest` runs before the request is built, like connection setup.
final class ScriptedSNTPTransport: SNTPTransport {
  private let lock = NSLock()
  private let beforeRequest: () -> Void
  private let reply: (Data) -> Result<Data, SNTPFailure>?
  private var recordedRequests: [Data] = []
  private var held: [(Result<Data, SNTPFailure>) -> Void] = []

  init(
    beforeRequest: @escaping () -> Void = {},
    reply: @escaping (Data) -> Result<Data, SNTPFailure>?
  ) {
    self.beforeRequest = beforeRequest
    self.reply = reply
  }

  var requests: [Data] {
    lock.lock()
    defer { lock.unlock() }
    return recordedRequests
  }

  func exchange(
    _ makeRequest: @escaping () -> Data,
    completion: @escaping (Result<Data, SNTPFailure>) -> Void
  ) {
    beforeRequest()
    let request = makeRequest()
    lock.lock()
    recordedRequests.append(request)
    lock.unlock()
    if let result = reply(request) {
      completion(result)
    } else {
      lock.lock()
      held.append(completion)
      lock.unlock()
    }
  }

  func completeHeld(with result: Result<Data, SNTPFailure>) {
    lock.lock()
    let completions = held
    held.removeAll()
    lock.unlock()
    completions.forEach { $0(result) }
  }
}

/// A wall clock that tests set by hand.
final class ManualWallClock {
  private let lock = NSLock()
  private var date: Date

  init(_ date: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
    self.date = date
  }

  func read() -> Date {
    lock.lock()
    defer { lock.unlock() }
    return date
  }

  func advance(by seconds: TimeInterval) {
    lock.lock()
    date = date.addingTimeInterval(seconds)
    lock.unlock()
  }
}

/// A tick that tests fire by hand.
final class ManualTick: RepeatingTick {
  private let lock = NSLock()
  private var handler: (() -> Void)?

  var isStarted: Bool {
    lock.lock()
    defer { lock.unlock() }
    return handler != nil
  }

  func start(_ handler: @escaping () -> Void) {
    lock.lock()
    self.handler = handler
    lock.unlock()
  }

  func fire() {
    lock.lock()
    let handler = handler
    lock.unlock()
    handler?()
  }
}

/// A `UserDefaults` suite that is empty when returned, so tests never touch the standard defaults.
func emptyDefaults(suiteName: String) -> UserDefaults {
  let defaults = UserDefaults(suiteName: suiteName)!
  defaults.removePersistentDomain(forName: suiteName)
  return defaults
}

/// Anchor storage writes run asynchronously. Waits up to 2 s for `condition`, then asserts it.
func waitUntil(
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line,
  _ condition: () -> Bool
) {
  let deadline = Date().addingTimeInterval(2)
  while !condition(), Date() < deadline {
    Thread.sleep(forTimeInterval: 0.001)
  }
  XCTAssertTrue(condition(), message(), file: file, line: line)
}
