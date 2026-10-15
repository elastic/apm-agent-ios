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
    private let iterations = 200

    func testAnchorUpdatesOverlapTimestampReadsAndSignalCreation() throws {
      let transport = ScriptedSNTPTransport {
        .success(sntpReply(to: $0, serverAhead: 30 * nanosPerSecond))
      }
      let synchronizer = NTPClockSynchronizer(transport: transport)
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
            .withRemoteManagement(false)
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
  }

#endif
