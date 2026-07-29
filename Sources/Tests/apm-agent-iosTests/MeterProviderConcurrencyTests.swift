// Copyright © 2022 Elasticsearch BV
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
import NIO
import OpenTelemetryApi
@testable import OpenTelemetrySdk
import XCTest
@testable import ElasticApm

/// Tracks overlapping ``export(metrics:)`` calls. Bookkeeping is thread-safe; export work itself is not
/// serialized, so concurrent callers can overlap during the deliberate sleep.
private final class RaceDetectingMetricExporter: MetricExporter {
  private let lock = NSLock()
  private var inFlight = false
  private(set) var exportCallCount = 0
  private(set) var detectedRaces = 0
  private(set) var exported: [[MetricData]] = []

  func export(metrics: [MetricData]) -> ExportResult {
    lock.lock()
    if inFlight {
      detectedRaces += 1
    }
    inFlight = true
    lock.unlock()

    Thread.sleep(forTimeInterval: 0.002)

    lock.lock()
    exportCallCount += 1
    exported.append(metrics)
    inFlight = false
    lock.unlock()
    return .success
  }

  func flush() -> ExportResult {
    .success
  }

  func shutdown() -> ExportResult {
    .success
  }

  func getAggregationTemporality(for instrument: InstrumentType) -> AggregationTemporality {
    .delta
  }

  func getDefaultAggregation(for instrument: InstrumentType) -> Aggregation {
    Aggregations.defaultAggregation()
  }
}

final class MeterProviderConcurrencyTests: XCTestCase {
  private var group: MultiThreadedEventLoopGroup!

  override func setUp() {
    super.setUp()
    group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
  }

  override func tearDown() {
    try? group?.syncShutdownGracefully()
    group = nil
    super.tearDown()
  }

  /// Documents that sharing an unsynchronized exporter across both meter providers races under concurrency.
  func testUnsynchronizedSharedExporterIsUnsafeAcrossBothMeterProviders() {
    let inner = RaceDetectingMetricExporter()
    let resource = Resource.empty

    let globalMeterProvider = makeGlobalMeterProvider(exporter: inner, resource: resource)
    let appRegistration = AppMetricsMeterProvider.register(metricExporter: inner, resource: resource)

    stressBothMeterProviders(
      globalMeterProvider: globalMeterProvider,
      appMeter: appRegistration.meter
    )

    XCTAssertGreaterThan(inner.exportCallCount, 0)
    XCTAssertGreaterThan(
      inner.detectedRaces,
      0,
      "expected overlapping export calls when the shared exporter is not synchronized"
    )
  }

  /// Verifies ``SynchronizedMetricExporter`` makes the shared exporter safe for both providers.
  func testSynchronizedSharedExporterIsSafeAcrossBothMeterProviders() {
    let inner = RaceDetectingMetricExporter()
    let sharedExporter = SynchronizedMetricExporter(inner: inner)
    let resource = Resource.empty

    let globalMeterProvider = makeGlobalMeterProvider(exporter: sharedExporter, resource: resource)
    let appRegistration = AppMetricsMeterProvider.register(
      metricExporter: sharedExporter,
      resource: resource
    )

    stressBothMeterProviders(
      globalMeterProvider: globalMeterProvider,
      appMeter: appRegistration.meter
    )

    XCTAssertGreaterThan(inner.exportCallCount, 0)
    XCTAssertEqual(
      inner.detectedRaces,
      0,
      "SynchronizedMetricExporter must serialize export calls from the global and AppMetrics providers"
    )
    XCTAssertEqual(inner.exported.count, inner.exportCallCount)
  }

  /// Production wiring: initializer exposes a synchronized exporter shared by both providers.
  func testOpenTelemetryInitializerExposesSynchronizedExporterSharedByBothProviders() {
    let inner = RaceDetectingMetricExporter()
    let sharedExporter = SynchronizedMetricExporter(inner: inner)
    let resource = Resource(attributes: [
      SemanticConventions.Service.name.rawValue: AttributeValue.string("exporter-concurrency-test")
    ])

    let initializer = OpenTelemetryInitializer(group: group, sessionSampler: SessionSampler { 1.0 })
    initializer.registerElasticMeterProvider(
      rawMetricExporter: sharedExporter,
      resource: resource,
      metricExportInterval: 60.0
    )
    let appRegistration = AppMetricsMeterProvider.register(
      metricExporter: sharedExporter,
      resource: resource
    )

    let globalMeterProvider = OpenTelemetry.instance.meterProvider as! MeterProviderSdk
    stressBothMeterProviders(
      globalMeterProvider: globalMeterProvider,
      appMeter: appRegistration.meter
    )

    XCTAssertGreaterThan(inner.exportCallCount, 0)
    XCTAssertEqual(inner.detectedRaces, 0)
  }

  private func stressBothMeterProviders(
    globalMeterProvider: MeterProviderSdk,
    appMeter: any Meter
  ) {
    let globalMeter = globalMeterProvider.meterBuilder(name: "Memory Sampler").build()
    let globalCounter = globalMeter.counterBuilder(name: "system.memory.usage").build()
    var appHistogram = appMeter.histogramBuilder(name: ElasticMetrics.appLaunchTime.rawValue).build()

    let iterations = 120
    let flushFailures = AtomicCounter()

    DispatchQueue.concurrentPerform(iterations: iterations) { index in
      if index.isMultiple(of: 2) {
        globalCounter.add(value: 1)
        if globalMeterProvider.forceFlush() != .success {
          flushFailures.increment()
        }
      } else {
        appHistogram.record(value: Double(index))
        MetricKitMetricExportSession.prepareExportForMetricKitPayload(
          start: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
          end: Date(timeIntervalSince1970: 1_700_008_640 + Double(index))
        )
        MetricKitMetricExportSession.flushMetricKitExport()
      }
    }

    XCTAssertEqual(flushFailures.value, 0)
  }

  private func makeGlobalMeterProvider(exporter: MetricExporter, resource: Resource) -> MeterProviderSdk {
    MeterProviderSdk.builder()
      .setResource(resource: resource)
      .registerView(
        selector: InstrumentSelector.builder().setInstrument(name: ".*").build(),
        view: View.builder().build()
      )
      .registerMetricReader(
        reader: PeriodicMetricReaderBuilder(exporter: exporter)
          .setInterval(timeInterval: 86_400)
          .build()
      )
      .build()
  }
}

/// Minimal atomic counter for concurrent test bookkeeping.
private final class AtomicCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  var value: Int {
    lock.lock()
    defer { lock.unlock() }
    return count
  }

  func increment() {
    lock.lock()
    count += 1
    lock.unlock()
  }
}
