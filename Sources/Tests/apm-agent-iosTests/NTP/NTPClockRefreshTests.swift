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

final class NTPClockRefreshTests: XCTestCase {
  // One suite per test, so a storage write that lands after a test ends cannot reach the next one.
  private let suiteName = "co.elastic.apm.tests.NTPClockRefreshTests." + UUID().uuidString
  private lazy var defaults = emptyDefaults(suiteName: suiteName)
  private var continuousClock = ManualContinuousClock()
  private let wallClock = ManualWallClock()

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    super.tearDown()
  }

  func testFirstLaunchSynchronizesAndSavesTheAnchorWithTheBootTime() throws {
    let tick = ManualTick()
    let synchronizer = makeSynchronizer(answeringTransport(), tick: tick)

    synchronizer.start()

    // Sent at 1_800_000_000 s wall and 1_000 s continuous; the reply arrives 0.2 s later.
    let anchor = try XCTUnwrap(synchronizer.anchor)
    XCTAssertEqual(Double(anchor.unixNanos) / 1e9, 1_800_000_030.2, accuracy: 1e-6)
    XCTAssertEqual(anchor.continuousNanos, 1_000_200_000_000)
    waitUntil {
      store.load() == .saved(.init(anchor: anchor, bootNanos: 1_799_998_999_800_000_000))
    }
    XCTAssertTrue(tick.isStarted)
  }

  func testSameBootRelaunchRestoresTheAnchorWithoutAnAttempt() throws {
    let anchor = try synchronizedLaunch()
    advanceBothClocks(by: 1_800)
    let transport = ScriptedSNTPTransport { _ in nil }
    let synchronizer = makeSynchronizer(transport)

    synchronizer.start()

    XCTAssertEqual(synchronizer.anchor, anchor)
    XCTAssertTrue(transport.requests.isEmpty)
    assertNow(synchronizer, equals: Date(timeIntervalSince1970: 1_800_000_030.2 + 1_800))
  }

  func testBootTimeShiftAboveOneSecondIsAReboot() throws {
    let anchor = try synchronizedLaunch()
    advanceBothClocks(by: 1_800)

    wallClock.advance(by: 0.5)
    let sameBoot = makeSynchronizer(ScriptedSNTPTransport { _ in nil })
    sameBoot.start()
    XCTAssertEqual(sameBoot.anchor, anchor)

    wallClock.advance(by: 1)
    let transport = ScriptedSNTPTransport { _ in nil }
    let rebooted = makeSynchronizer(transport)
    rebooted.start()
    XCTAssertNil(rebooted.anchor)
    waitUntil { store.load() == .absent }
    XCTAssertEqual(transport.requests.count, 1)
    assertNow(rebooted, equals: wallClock.read())
  }

  func testContinuousClockBehindTheSavedValueIsAReboot() throws {
    _ = try synchronizedLaunch()
    // Keep the derived boot time equal, so only the continuous clock signals the reboot.
    continuousClock = ManualContinuousClock(nanos: 10 * UInt64(nanosPerSecond))
    wallClock.advance(by: -990.2)
    let synchronizer = makeSynchronizer(ScriptedSNTPTransport { _ in nil })

    synchronizer.start()

    XCTAssertNil(synchronizer.anchor)
    waitUntil { store.load() == .absent }
  }

  func testMalformedSavedValuesAreRejectedAndRemoved() throws {
    _ = try synchronizedLaunch()
    let valid = try XCTUnwrap(defaults.data(forKey: NTPAnchorStore.key))
    var unknownVersion = valid
    unknownVersion[0] = 2
    let malformed: [Any] = ["anchor", valid.prefix(17), unknownVersion]

    for value in malformed {
      defaults.set(value, forKey: NTPAnchorStore.key)
      let synchronizer = makeSynchronizer(ScriptedSNTPTransport { _ in nil })

      synchronizer.start()

      XCTAssertNil(synchronizer.anchor, "\(value)")
      waitUntil("\(value)") { defaults.object(forKey: NTPAnchorStore.key) == nil }
    }
  }

  func testSavedAnchorAged24HoursIsRejected() throws {
    let anchor = try synchronizedLaunch()

    advanceBothClocks(by: 24 * 3_600 - 1)
    let transport = ScriptedSNTPTransport { _ in nil }
    let lastValid = makeSynchronizer(transport)
    lastValid.start()
    XCTAssertEqual(lastValid.anchor, anchor)
    // Older than 1 hour, so it is refreshed.
    XCTAssertEqual(transport.requests.count, 1)

    advanceBothClocks(by: 1)
    let expired = makeSynchronizer(ScriptedSNTPTransport { _ in nil })
    expired.start()
    XCTAssertNil(expired.anchor)
    waitUntil { store.load() == .absent }
  }

  func testFailedRefreshKeepsTheAnchorUntilATickDiscardsIt() throws {
    var replies = true
    let transport = ScriptedSNTPTransport { [continuousClock] request in
      guard replies else {
        return .failure(.timeout)
      }
      continuousClock.advance(by: 200_000_000)
      return .success(sntpReply(to: request, serverAhead: 30_100_000_000))
    }
    let tick = ManualTick()
    let synchronizer = makeSynchronizer(transport, tick: tick)
    synchronizer.start()
    let anchor = try XCTUnwrap(synchronizer.anchor)
    waitForSaved(anchor)
    let saved = store.load()
    replies = false

    advanceBothClocks(by: 3_600)
    tick.fire()
    XCTAssertEqual(transport.requests.count, 2)
    XCTAssertEqual(synchronizer.anchor, anchor)
    XCTAssertEqual(store.load(), saved)

    advanceBothClocks(by: 23 * 3_600)
    tick.fire()
    XCTAssertEqual(transport.requests.count, 3)
    XCTAssertNil(synchronizer.anchor)
    waitUntil { store.load() == .absent }
    assertNow(synchronizer, equals: wallClock.read())
  }

  func testWallClockChangeBetweenLaunchesOnlyCausesACacheMiss() throws {
    _ = try synchronizedLaunch()
    continuousClock.advance(by: 60 * nanosPerSecond)
    wallClock.advance(by: 3_600)
    let synchronizer = makeSynchronizer(ScriptedSNTPTransport { _ in nil })

    synchronizer.start()

    XCTAssertNil(synchronizer.anchor)
    assertNow(synchronizer, equals: wallClock.read())
    waitUntil { store.load() == .absent }
  }

  func testTickRefreshesWhenTheAnchorIsAnHourOld() throws {
    let tick = ManualTick()
    let transport = answeringTransport()
    let synchronizer = makeSynchronizer(transport, tick: tick)
    synchronizer.start()
    XCTAssertEqual(transport.requests.count, 1)

    advanceBothClocks(by: 59 * 60)
    tick.fire()
    XCTAssertEqual(transport.requests.count, 1)

    advanceBothClocks(by: 60)
    tick.fire()
    XCTAssertEqual(transport.requests.count, 2)
    waitForSaved(try XCTUnwrap(synchronizer.anchor))
  }

  func testTickRetriesUntilTheFirstSuccess() throws {
    var replies = false
    let transport = ScriptedSNTPTransport { request in
      replies ? .success(sntpReply(to: request, serverAhead: 30 * nanosPerSecond)) : .failure(.timeout)
    }
    let tick = ManualTick()
    let synchronizer = makeSynchronizer(transport, tick: tick)
    synchronizer.start()

    for _ in 0..<3 {
      advanceBothClocks(by: 60)
      tick.fire()
    }
    XCTAssertEqual(transport.requests.count, 4)
    XCTAssertNil(synchronizer.anchor)

    replies = true
    advanceBothClocks(by: 60)
    tick.fire()
    XCTAssertNotNil(synchronizer.anchor)

    advanceBothClocks(by: 60)
    tick.fire()
    XCTAssertEqual(transport.requests.count, 5)
    waitForSaved(try XCTUnwrap(synchronizer.anchor))
  }

  func testFailedRefreshRetriesEveryTickUntilItSucceeds() throws {
    var replies = true
    let transport = ScriptedSNTPTransport { request in
      replies ? .success(sntpReply(to: request, serverAhead: 30 * nanosPerSecond)) : .failure(.timeout)
    }
    let tick = ManualTick()
    let synchronizer = makeSynchronizer(transport, tick: tick)
    synchronizer.start()
    let firstAnchor = try XCTUnwrap(synchronizer.anchor)

    replies = false
    advanceBothClocks(by: 60 * 60)
    tick.fire()
    advanceBothClocks(by: 60)
    tick.fire()
    // The start attempt plus one attempt per failed tick.
    XCTAssertEqual(transport.requests.count, 3)
    XCTAssertEqual(synchronizer.anchor, firstAnchor)

    replies = true
    advanceBothClocks(by: 60)
    tick.fire()
    XCTAssertEqual(transport.requests.count, 4)
    let refreshedAnchor = try XCTUnwrap(synchronizer.anchor)
    XCTAssertNotEqual(refreshedAnchor, firstAnchor)
    XCTAssertEqual(refreshedAnchor.continuousNanos, continuousClock.read())

    // The next refresh is due an hour after the refreshed anchor.
    advanceBothClocks(by: 60)
    tick.fire()
    XCTAssertEqual(transport.requests.count, 4)
    waitForSaved(refreshedAnchor)
  }

  func testDefaultsObserversThatReadTheClockDoNotDeadlock() throws {
    let tick = ManualTick()
    let synchronizer = makeSynchronizer(answeringTransport(), tick: tick)
    // `queue: nil` runs the observer synchronously on the thread that changes the defaults.
    let observer = NotificationCenter.default.addObserver(
      forName: UserDefaults.didChangeNotification, object: defaults, queue: nil
    ) { _ in
      _ = synchronizer.now
      _ = synchronizer.anchor
    }
    defer { NotificationCenter.default.removeObserver(observer) }
    let finished = expectation(description: "synchronizations and expiry finish")

    DispatchQueue.global().async { [self] in
      synchronizer.start()
      // A day later the tick discards the anchor, removes it, and synchronizes again.
      advanceBothClocks(by: 24 * 3_600)
      tick.fire()
      finished.fulfill()
    }

    guard XCTWaiter.wait(for: [finished], timeout: 2) == .completed else {
      // The worker still holds the clock lock, so reading the anchor here would hang.
      XCTFail("A defaults observer that reads the clock deadlocked")
      return
    }
    // The anchor from the synchronization after the expiry, saved after the removal.
    let anchor = try XCTUnwrap(synchronizer.anchor)
    XCTAssertEqual(anchor.continuousNanos, continuousClock.read())
    waitForSaved(anchor)
  }

  func testOverlappingTicksStartOneAttemptAndReadsDoNotWait() {
    let tick = ManualTick()
    let transport = ScriptedSNTPTransport { _ in nil }
    let synchronizer = makeSynchronizer(transport, tick: tick)
    synchronizer.start()

    DispatchQueue.concurrentPerform(iterations: 10) { _ in tick.fire() }

    XCTAssertEqual(transport.requests.count, 1)
    assertNow(synchronizer, equals: wallClock.read())
  }

  func testAnchorThatOverflowsFallsBackToTheSystemClock() throws {
    let anchor = NTPClockSynchronizer.Anchor(
      unixNanos: .max, continuousNanos: continuousClock.read() - UInt64(nanosPerSecond))
    // Saved in this boot: wall clock minus continuous clock, as the synchronizer derives it.
    let bootNanos = Int64(wallClock.read().timeIntervalSince1970 * 1e9) - Int64(continuousClock.read())
    store.save(.init(anchor: anchor, bootNanos: bootNanos))
    let synchronizer = makeSynchronizer(ScriptedSNTPTransport { _ in nil })

    synchronizer.start()
    advanceBothClocks(by: 60)

    XCTAssertEqual(synchronizer.anchor, anchor)
    assertNow(synchronizer, equals: wallClock.read())
  }

  func testStartWithoutATransportReadsNoSavedAnchorAndStartsNoTick() throws {
    _ = try synchronizedLaunch()
    let saved = store.load()
    let tick = ManualTick()
    let synchronizer = makeSynchronizer(nil, tick: tick)

    synchronizer.start()

    XCTAssertNil(synchronizer.anchor)
    XCTAssertFalse(tick.isStarted)
    XCTAssertEqual(store.load(), saved)
  }

  // MARK: - Helpers

  private var store: NTPAnchorStore {
    NTPAnchorStore(userDefaults: defaults)
  }

  /// One launch that synchronizes and saves its anchor.
  private func synchronizedLaunch() throws -> NTPClockSynchronizer.Anchor {
    let synchronizer = makeSynchronizer(answeringTransport())
    synchronizer.start()
    let anchor = try XCTUnwrap(synchronizer.anchor)
    waitForSaved(anchor)
    return anchor
  }

  private func waitForSaved(
    _ anchor: NTPClockSynchronizer.Anchor,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    waitUntil(file: file, line: line) {
      if case let .saved(saved) = store.load() {
        return saved.anchor == anchor
      }
      return false
    }
  }

  /// Answers after 0.2 s of continuous time, from a server clock 30.1 s ahead of the request.
  private func answeringTransport() -> ScriptedSNTPTransport {
    ScriptedSNTPTransport { [continuousClock] request in
      continuousClock.advance(by: 200_000_000)
      return .success(sntpReply(to: request, serverAhead: 30_100_000_000))
    }
  }

  private func makeSynchronizer(
    _ transport: SNTPTransport?,
    tick: RepeatingTick = ManualTick()
  ) -> NTPClockSynchronizer {
    NTPClockSynchronizer(
      transport: transport,
      userDefaults: defaults,
      tick: tick,
      continuousClock: continuousClock.read,
      wallClock: wallClock.read)
  }

  /// Time passing within one boot.
  private func advanceBothClocks(by seconds: TimeInterval) {
    continuousClock.advance(by: Int64(seconds * 1e9))
    wallClock.advance(by: seconds)
  }

  private func assertNow(
    _ synchronizer: NTPClockSynchronizer,
    equals expected: Date,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(
      synchronizer.now.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1e-6,
      file: file, line: line)
  }
}
