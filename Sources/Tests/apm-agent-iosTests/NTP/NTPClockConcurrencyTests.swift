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
      let transport = ScriptedSNTPTransport {
        .success(sntpReply(to: $0, serverAhead: 30 * nanosPerSecond))
      }
      let makeSynchronizer = { (tick: RepeatingTick) in
        NTPClockSynchronizer(
          transport: transport,
          userDefaults: self.defaults,
          tick: tick,
          continuousClock: continuousClock.read,
          wallClock: wallClock.read)
      }
      // A previous launch in this boot saves the anchor that the next start restores.
      let previousLaunch = makeSynchronizer(ManualTick())
      previousLaunch.synchronize()
      let previousAnchor = try XCTUnwrap(previousLaunch.anchor)
      let store = NTPAnchorStore(userDefaults: defaults)
      waitUntil {
        if case let .saved(record) = store.load() {
          return record.anchor == previousAnchor
        }
        return false
      }
      let tick = ManualTick()
      let synchronizer = makeSynchronizer(tick)
      let day = 24 * 3_600 * nanosPerSecond

      DispatchQueue.concurrentPerform(iterations: 3) { worker in
        switch worker {
        case 0:
          synchronizer.start()
          // Each tick finds the anchor a day old, discards it, and synchronizes again.
          for _ in 0..<iterations {
            continuousClock.advance(by: day)
            wallClock.advance(by: TimeInterval(day / nanosPerSecond))
            tick.fire()
          }
        case 1:
          for _ in 0..<iterations * 10 { _ = synchronizer.now }
        default:
          for _ in 0..<iterations * 10 { _ = synchronizer.anchor }
        }
      }

      XCTAssertTrue(tick.isStarted)
      XCTAssertEqual(transport.requests.count, 1 + iterations)
      let finalAnchor = try XCTUnwrap(synchronizer.anchor)
      waitUntil {
        if case let .saved(record) = store.load() {
          return record.anchor == finalAnchor
        }
        return false
      }
    }
  }

#endif
