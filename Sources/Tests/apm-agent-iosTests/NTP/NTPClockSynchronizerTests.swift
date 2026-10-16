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

#if !os(watchOS)
  import ElasticApmTestSupport
#endif

@testable import ElasticApm

final class NTPClockSynchronizerTests: XCTestCase {
  private static let suiteName = "co.elastic.apm.tests.NTPClockSynchronizerTests"
  private let defaults = emptyDefaults(suiteName: suiteName)
  private let wallTime = Date(timeIntervalSince1970: 1_800_000_000)
  private let continuousClock = ManualContinuousClock()

  override func tearDown() {
    defaults.removePersistentDomain(forName: Self.suiteName)
    super.tearDown()
  }

  func testTimestampsUseTheSystemClockBeforeSynchronization() {
    let synchronizer = NTPClockSynchronizer(
      transport: ScriptedSNTPTransport { _ in nil }, userDefaults: defaults)

    synchronizer.synchronize()

    assertSystemClock(synchronizer)
  }

  func testTimestampsUseTheSystemClockAfterAFailedAttempt() {
    let synchronizer = NTPClockSynchronizer(
      transport: ScriptedSNTPTransport { _ in .failure(.timeout) }, userDefaults: defaults)

    synchronizer.synchronize()

    XCTAssertNil(synchronizer.anchor)
    assertSystemClock(synchronizer)
  }

  func testValidReplySetsAnAnchorThatAdvancesWithTheContinuousClock() {
    let synchronizer = makeSynchronizer(transport: answeringTransport())

    synchronizer.synchronize()
    continuousClock.advance(by: 5 * nanosPerSecond)

    // Offset ((30.1 s) + (30.1 s - 0.2 s)) / 2 = 30 s, applied at the reply (+0.2 s), then +5 s.
    assertNow(synchronizer, equals: wallTime.addingTimeInterval(35.2))
  }

  func testWallClockChangeDuringTheExchangeDoesNotShiftTheAnchor() {
    var currentWallTime = wallTime
    let transport = ScriptedSNTPTransport { [continuousClock] request in
      currentWallTime = currentWallTime.addingTimeInterval(3_600)
      continuousClock.advance(by: 200_000_000)
      return .success(sntpReply(to: request, serverAhead: 30_100_000_000))
    }
    let synchronizer = NTPClockSynchronizer(
      transport: transport,
      userDefaults: defaults,
      continuousClock: continuousClock.read,
      wallClock: { currentWallTime })

    synchronizer.synchronize()
    continuousClock.advance(by: 5 * nanosPerSecond)

    assertNow(synchronizer, equals: wallTime.addingTimeInterval(35.2))
  }

  func testRejectedRepliesAndFailedAttemptsKeepTheExistingAnchor() throws {
    var nextReply: ((Data) -> Result<Data, SNTPFailure>)?
    let transport = ScriptedSNTPTransport { request in nextReply?(request) }
    let synchronizer = makeSynchronizer(transport: transport)
    nextReply = { .success(sntpReply(to: $0, serverAhead: 30 * nanosPerSecond)) }
    synchronizer.synchronize()
    let anchor = try XCTUnwrap(synchronizer.anchor)

    let rejected = rejectedSNTPReplies(to: transport.requests[0]).map { $0.1 }
    for reply in rejected {
      nextReply = { _ in .success(reply) }
      synchronizer.synchronize()
      XCTAssertEqual(synchronizer.anchor, anchor)
    }
    for failure in [SNTPFailure.timeout, .connectionFailed, .cancelled] {
      nextReply = { _ in .failure(failure) }
      synchronizer.synchronize()
      XCTAssertEqual(synchronizer.anchor, anchor)
    }
    XCTAssertEqual(transport.requests.count, 1 + rejected.count + 3)
  }

  func testReplyLaterThanTheDeadlineAfterSendingIsRejected() {
    let deadline = Int64(SNTPAttempt.deadline * 1e9)
    var roundTrip = deadline + 1
    let transport = ScriptedSNTPTransport { [continuousClock] request in
      continuousClock.advance(by: roundTrip)
      return .success(sntpReply(to: request, serverAhead: 30 * nanosPerSecond))
    }
    let synchronizer = NTPClockSynchronizer(
      transport: transport, userDefaults: defaults, continuousClock: continuousClock.read)

    synchronizer.synchronize()

    XCTAssertNil(synchronizer.anchor)
    assertSystemClock(synchronizer)

    roundTrip = deadline
    synchronizer.synchronize()

    XCTAssertNotNil(synchronizer.anchor)
  }

  func testConnectionSetupBeforeSendingDoesNotChangeTheAnchor() {
    let setupDelay = 3 * nanosPerSecond

    let delayed = anchorAfterExchange(startingAfter: 0, setupDelay: setupDelay)
    let immediate = anchorAfterExchange(startingAfter: setupDelay, setupDelay: 0)

    XCTAssertNotNil(delayed)
    XCTAssertEqual(delayed, immediate)
  }

  func testOnlyOneAttemptRunsAtATime() {
    let transport = ScriptedSNTPTransport { _ in nil }
    let synchronizer = makeSynchronizer(transport: transport)

    synchronizer.synchronize()
    synchronizer.synchronize()
    synchronizer.synchronize()
    XCTAssertEqual(transport.requests.count, 1)

    transport.completeHeld(with: .failure(.timeout))
    synchronizer.synchronize()
    XCTAssertEqual(transport.requests.count, 2)
  }

  func testDisabledAgentAndInvalidEndpointStartNoAttempt() throws {
    // A saved anchor from this boot that a restore would install.
    let saved = makeSynchronizer(
      transport: ScriptedSNTPTransport { .success(sntpReply(to: $0, serverAhead: 30 * nanosPerSecond)) })
    saved.synchronize()
    let savedAnchor = try XCTUnwrap(saved.anchor)
    waitUntil {
      if case let .saved(record) = NTPAnchorStore(userDefaults: defaults).load() {
        return record.anchor == savedAnchor
      }
      return false
    }
    let transport = ScriptedSNTPTransport { _ in nil }
    let tick = ManualTick()
    let synchronizer = NTPClockSynchronizer(
      transport: transport,
      userDefaults: defaults,
      tick: tick,
      continuousClock: continuousClock.read,
      wallClock: { [wallTime] in wallTime })

    ElasticApmAgent.start(
      with: AgentConfigBuilder().disableAgent().build(),
      InstrumentationConfiguration(),
      clockSynchronizer: synchronizer)
    ElasticApmAgent.start(
      with: AgentConfigBuilder().withExportUrl(URL(string: "ftp://collector.example.com")!).build(),
      InstrumentationConfiguration(),
      clockSynchronizer: synchronizer)

    XCTAssertNil(ElasticApmAgent.shared())
    XCTAssertTrue(transport.requests.isEmpty)
    XCTAssertNil(synchronizer.anchor)
    XCTAssertFalse(tick.isStarted)
    // Control: starting the same synchronizer restores the anchor and starts the tick.
    synchronizer.start()
    XCTAssertEqual(synchronizer.anchor, savedAnchor)
    XCTAssertTrue(tick.isStarted)
    synchronizer.synchronize()
    XCTAssertEqual(transport.requests.count, 1)
  }

  #if !os(watchOS)
    // The UDP transport does not exist on watchOS.
    func testReplyAfterTheDeadlinePublishesNothing() throws {
      let server = try LoopbackUDPTestServer(replyDelay: 0.6) { request in
        sntpReply(to: request, serverAhead: 30 * nanosPerSecond)
      }
      defer { server.close() }
      let synchronizer = NTPClockSynchronizer(
        transport: SNTPUDPTransport(host: "127.0.0.1", port: server.port, deadline: 0.2),
        userDefaults: defaults)

      synchronizer.synchronize()
      Thread.sleep(forTimeInterval: 1.0)

      XCTAssertEqual(server.receivedRequestCount, 1)
      XCTAssertNil(synchronizer.anchor)
      assertSystemClock(synchronizer)
      // The timed-out attempt has finished, so a new one can start.
      synchronizer.synchronize()
      let deadline = Date().addingTimeInterval(2)
      while server.receivedRequestCount < 2, Date() < deadline {
        Thread.sleep(forTimeInterval: 0.01)
      }
      XCTAssertEqual(server.receivedRequestCount, 2)
    }
  #endif

  // MARK: - Helpers

  /// Answers after 0.2 s of continuous time, from a server clock 30.1 s ahead of the request.
  private func answeringTransport() -> ScriptedSNTPTransport {
    ScriptedSNTPTransport { [continuousClock] request in
      continuousClock.advance(by: 200_000_000)
      return .success(sntpReply(to: request, serverAhead: 30_100_000_000))
    }
  }

  /// Runs one exchange with both clocks starting `start` after the fixture time. Connection
  /// setup advances both clocks by `setupDelay`; the reply arrives 0.2 s after sending.
  private func anchorAfterExchange(
    startingAfter start: Int64,
    setupDelay: Int64
  ) -> NTPClockSynchronizer.Anchor? {
    let continuous = ManualContinuousClock()
    continuous.advance(by: start)
    var currentWallTime = wallTime.addingTimeInterval(Double(start) / 1e9)
    let transport = ScriptedSNTPTransport(
      beforeRequest: {
        continuous.advance(by: setupDelay)
        currentWallTime = currentWallTime.addingTimeInterval(Double(setupDelay) / 1e9)
      },
      reply: { request in
        continuous.advance(by: 200_000_000)
        return .success(sntpReply(to: request, serverAhead: 30_100_000_000))
      })
    let synchronizer = NTPClockSynchronizer(
      transport: transport,
      userDefaults: defaults,
      continuousClock: continuous.read,
      wallClock: { currentWallTime })

    synchronizer.synchronize()

    return synchronizer.anchor
  }

  private func makeSynchronizer(transport: SNTPTransport) -> NTPClockSynchronizer {
    NTPClockSynchronizer(
      transport: transport,
      userDefaults: defaults,
      continuousClock: continuousClock.read,
      wallClock: { [wallTime] in wallTime })
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

  private func assertSystemClock(
    _ synchronizer: NTPClockSynchronizer,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let before = Date()
    let now = synchronizer.now
    let after = Date()
    XCTAssertTrue((before...after).contains(now), "\(now) is not the system clock", file: file, line: line)
  }
}
