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

// EDOT supports iOS; macOS retains the SwiftPM development loop and runs this test under
// ThreadSanitizer.
#if os(iOS) || os(macOS)

  import ElasticApmTestSupport
  import Foundation
  import NIO
  import OpenTelemetryApi
  import OpenTelemetrySdk
  import XCTest

  @testable import ElasticApm

  final class NTPClockConcurrencyTests: XCTestCase {
    // One suite per test, so a storage write that lands after a test ends cannot reach the next one.
    private let suiteName = "co.elastic.apm.tests.NTPClockConcurrencyTests." + UUID().uuidString
    private lazy var defaults = emptyDefaults(suiteName: suiteName)
    private let iterations = 200

    override func tearDown() {
      defaults.removePersistentDomain(forName: suiteName)
      super.tearDown()
    }

    func testAnchorUpdatesOverlapTimestampReadsAndSignalCreation() throws {
      let transport = ScriptedSNTPTransport {
        .success(sntpReply(to: $0, serverAhead: 30 * nanosPerSecond))
      }
      let synchronizer = NTPClockSynchronizer(transport: transport, userDefaults: defaults)
      let clock = NTPClock(synchronizer: synchronizer)
      let spanExporter = WaitingSpanExporter(numberToWaitFor: iterations)
      let logExporter = WaitingLogRecordExporter(numberToWaitFor: iterations)
      let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
      defer { XCTAssertNoThrow(try group.syncShutdownGracefully()) }
      let initializer = OpenTelemetryInitializer(
        group: group,
        sessionSampler: SessionSampler { 1.0 },
        exporters: OpenTelemetryInitializer.Exporters(
          metric: WaitingMetricExporter(numberToWaitFor: 1),
          trace: spanExporter,
          log: logExporter),
        clockSynchronizer: synchronizer)
      _ = initializer.initializeWithHttp(
        AgentConfigManager(
          resource: Resource(),
          config: AgentConfigBuilder()
            .withExportUrl(URL(string: "http://127.0.0.1:9")!)
            .build(),
          instrumentationConfig: InstrumentationConfigBuilder()
            .withLifecycleEvents(false)
            .withViewControllerInstrumentation(false)
            .withSystemMetrics(false)
            .build(),
          endpointRegistry: SDKEndpointRegistry()))
      let tracerProvider = try XCTUnwrap(
        OpenTelemetry.instance.tracerProvider as? TracerProviderSdk)
      let loggerProvider = try XCTUnwrap(
        OpenTelemetry.instance.loggerProvider as? LoggerProviderSdk)
      defer { tracerProvider.shutdown() }
      let tracer = tracerProvider.get(instrumentationName: "NTPClockConcurrencyTests")
      let logger = loggerProvider.loggerBuilder(instrumentationScopeName: "NTPClockConcurrencyTests")
        .build()
      let start = Date()

      DispatchQueue.concurrentPerform(iterations: 4) { worker in
        switch worker {
        case 0:
          for _ in 0..<iterations { synchronizer.synchronize() }
        case 1:
          for _ in 0..<iterations * 10 { _ = clock.now }
        case 2:
          for _ in 0..<iterations { tracer.spanBuilder(spanName: "concurrent-span").startSpan().end() }
        default:
          for _ in 0..<iterations { logger.logRecordBuilder().setEventName("concurrent-log").emit() }
        }
      }
      tracerProvider.forceFlush()

      XCTAssertEqual(transport.requests.count, iterations)
      let spans = try XCTUnwrap(spanExporter.waitForExport())
      let logs = try XCTUnwrap(logExporter.waitForExport())
      // Each timestamp comes from the system clock or from the anchor, about 30 s ahead.
      let latest = Date().addingTimeInterval(31)
      for timestamp in spans.map(\.startTime) + logs.map(\.timestamp) {
        XCTAssertTrue((start...latest).contains(timestamp), "\(timestamp) is outside \(start)...\(latest)")
      }
      XCTAssertEqual(clock.now.timeIntervalSinceNow, 30, accuracy: 1)
    }

    func testRestoreAndTicksOverlapTimestampReads() throws {
      let continuousClock = ManualContinuousClock()
      let wallClock = ManualWallClock()
      let storage = GatedAnchorDefaults(suiteName: suiteName)!
      let store = NTPAnchorStore(userDefaults: storage)
      let initialAnchor = NTPClockSynchronizer.Anchor(
        unixNanos: Int64(wallClock.read().timeIntervalSince1970 * 1e9) + 30 * nanosPerSecond,
        continuousNanos: continuousClock.read())
      let bootNanos = Int64(wallClock.read().timeIntervalSince1970 * 1e9)
        - Int64(continuousClock.read())
      store.save(.init(anchor: initialAnchor, bootNanos: bootNanos))
      let transport = ScriptedSNTPTransport { _ in nil }
      let tick = ManualTick()
      let synchronizer = NTPClockSynchronizer(
        transport: transport, userDefaults: storage, tick: tick,
        continuousClock: continuousClock.read, wallClock: wallClock.read)

      // An hour-old restored anchor remains readable while its startup refresh is pending.
      continuousClock.advance(by: 3_600 * nanosPerSecond)
      wallClock.advance(by: 3_600)
      synchronizer.start()
      XCTAssertTrue(tick.isStarted)
      XCTAssertEqual(transport.requests.count, 1)
      assertConcurrentReads(synchronizer, anchors: [initialAnchor], dates: [wallClock.read().addingTimeInterval(30)])
      transport.completeHeld(with: .success(sntpReply(to: transport.requests[0], serverAhead: 30 * nanosPerSecond)))
      let refreshed = try XCTUnwrap(synchronizer.anchor)
      waitForSaved(refreshed, bootNanos: bootNanos, store: store, storage: storage)

      // Hold the real storage removal. Timestamp readers and the next reply must finish first.
      defer { storage.allowRemoval.signal() }
      continuousClock.advance(by: 24 * 3_600 * nanosPerSecond)
      wallClock.advance(by: 24 * 3_600)
      tick.fire()
      guard storage.removalStarted.wait(timeout: .now() + 2) == .success else {
        XCTFail("Expiry did not reach storage removal; observed \(store.load())")
        return
      }
      XCTAssertEqual(transport.requests.count, 2)
      assertConcurrentReads(synchronizer, anchors: [nil], dates: [wallClock.read()])
      let finalAnchor = NTPClockSynchronizer.Anchor(
        unixNanos: Int64(wallClock.read().timeIntervalSince1970 * 1e9) + 42 * nanosPerSecond,
        continuousNanos: continuousClock.read())
      let replyFinished = expectation(description: "refresh callback finishes with persistence held")
      DispatchQueue.global().async {
        transport.completeHeld(with: .success(sntpReply(to: transport.requests[1], serverAhead: 42 * nanosPerSecond)))
        replyFinished.fulfill()
      }
      assertConcurrentReads(
        synchronizer, anchors: [nil, finalAnchor],
        dates: [wallClock.read(), wallClock.read().addingTimeInterval(42)])
      guard XCTWaiter.wait(for: [replyFinished], timeout: 2) == .completed else {
        XCTFail("Refresh callback waited for persistence")
        return
      }
      assertConcurrentReads(synchronizer, anchors: [finalAnchor], dates: [wallClock.read().addingTimeInterval(42)])
      XCTAssertEqual(store.load(), .saved(.init(anchor: refreshed, bootNanos: bootNanos)))
      storage.allowRemoval.signal()
      waitForSaved(finalAnchor, bootNanos: bootNanos, store: store, storage: storage)
      XCTAssertEqual(storage.writes, [
        .saved(.init(anchor: initialAnchor, bootNanos: bootNanos)),
        .saved(.init(anchor: refreshed, bootNanos: bootNanos)),
        .absent,
        .saved(.init(anchor: finalAnchor, bootNanos: bootNanos))
      ])
    }

    private func assertConcurrentReads(
      _ synchronizer: NTPClockSynchronizer,
      anchors: [NTPClockSynchronizer.Anchor?],
      dates: [Date],
      file: StaticString = #filePath, line: UInt = #line
    ) {
      let readers = (0..<2).map { expectation(description: "timestamp reader \($0) finishes") }
      for reader in readers {
        DispatchQueue.global().async {
          for _ in 0..<32 {
            XCTAssertTrue(anchors.contains(synchronizer.anchor), "Incomplete or unexpected anchor", file: file, line: line)
            let timestamp = synchronizer.now
            XCTAssertTrue(dates.contains { abs($0.timeIntervalSince(timestamp)) < 1e-6 },
                          "Unexpected timestamp \(timestamp); expected one of \(dates)", file: file, line: line)
          }
          reader.fulfill()
        }
      }
      XCTAssertEqual(XCTWaiter.wait(for: readers, timeout: 2), .completed,
                     "Timestamp readers waited for pending work", file: file, line: line)
    }

    private func waitForSaved(
      _ anchor: NTPClockSynchronizer.Anchor, bootNanos: Int64,
      store: NTPAnchorStore, storage: GatedAnchorDefaults,
      file: StaticString = #filePath, line: UInt = #line
    ) {
      let expected = NTPAnchorStore.Loaded.saved(.init(anchor: anchor, bootNanos: bootNanos))
      // Only three asynchronous writes are queued; retain the existing two-second deadline.
      waitUntil("Expected \(expected); observed \(store.load()); completed writes: \(storage.writes)", file: file, line: line) {
        store.load() == expected && storage.writes.last == expected
      }
    }
  }

  /// Uses real suite persistence, holding expiry removal to prove reads never wait for storage.
  private final class GatedAnchorDefaults: UserDefaults {
    let removalStarted = DispatchSemaphore(value: 0)
    let allowRemoval = DispatchSemaphore(value: 0)
    private let writeLock = NSLock()
    private var completedWrites: [NTPAnchorStore.Loaded] = []

    var writes: [NTPAnchorStore.Loaded] {
      writeLock.lock()
      defer { writeLock.unlock() }
      return completedWrites
    }

    override func set(_ value: Any?, forKey key: String) {
      super.set(value, forKey: key)
      if key == NTPAnchorStore.key { recordWrite() }
    }

    override func removeObject(forKey key: String) {
      if key == NTPAnchorStore.key {
        removalStarted.signal()
        // A broken test must release its worker even if the test's cleanup cannot run.
        XCTAssertEqual(allowRemoval.wait(timeout: .now() + 10), .success, "Test did not release storage removal")
      }
      super.removeObject(forKey: key)
      if key == NTPAnchorStore.key { recordWrite() }
    }

    private func recordWrite() {
      let value = NTPAnchorStore(userDefaults: self).load()
      writeLock.lock()
      // UserDefaults can implement removal through set(nil); record state transitions.
      if completedWrites.last != value { completedWrites.append(value) }
      writeLock.unlock()
    }
  }

#endif
