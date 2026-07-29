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

private final class CapturingMetricExporter: MetricExporter {
  private(set) var exported: [[MetricData]] = []

  func export(metrics: [MetricData]) -> ExportResult {
    exported.append(metrics)
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

private final class StubMetricProducer: MetricProducer {
  var metrics: [MetricData] = []

  func collectAllMetrics() -> [MetricData] {
    metrics
  }
}

final class MetricKitMetricExporterTests: XCTestCase {
  func testMetricKitTriggeredMetricReaderExportsCollectedMetrics() {
    let inner = CapturingMetricExporter()
    let sut = MetricKitTriggeredMetricReader(exporter: inner)
    let producer = StubMetricProducer()
    producer.metrics = [
      MetricData.createLongSum(
        resource: Resource.empty,
        instrumentationScopeInfo: InstrumentationScopeInfo(name: AppMetricsMeter.scopeName),
        name: "application.exits",
        description: "",
        unit: "ms",
        isMonotonic: false,
        data: SumData(aggregationTemporality: .delta, points: [])
      ),
      MetricData.createLongSum(
        resource: Resource.empty,
        instrumentationScopeInfo: InstrumentationScopeInfo(name: "MemorySampler"),
        name: "cpu",
        description: "",
        unit: "",
        isMonotonic: false,
        data: SumData(aggregationTemporality: .delta, points: [])
      )
    ]
    sut.register(registration: producer)
    sut.setPendingExportWindow(
      start: Date(timeIntervalSince1970: 1_700_000_000),
      end: Date(timeIntervalSince1970: 1_700_008_640)
    )

    XCTAssertEqual(sut.forceFlush(), .success)
    XCTAssertEqual(inner.exported.count, 1)
    XCTAssertEqual(inner.exported[0].count, 2)
  }

  func testMetricKitTriggeredMetricReaderSuccessWhenNoProducer() {
    let inner = CapturingMetricExporter()
    let sut = MetricKitTriggeredMetricReader(exporter: inner)
    XCTAssertEqual(sut.forceFlush(), .success)
    XCTAssertTrue(inner.exported.isEmpty)
  }

  func testMetricKitTriggeredMetricReaderUsesDeltaTemporalityForHistograms() {
    let inner = CapturingMetricExporter()
    let sut = MetricKitTriggeredMetricReader(exporter: inner)
    XCTAssertEqual(sut.getAggregationTemporality(for: .histogram), .delta)
    XCTAssertEqual(sut.getAggregationTemporality(for: .counter), .delta)
  }

  func testApplicationMetricsMeterProviderPropagatesServiceNameOnExport() {
    let exporter = CapturingMetricExporter()
    let resource = Resource(attributes: [
      SemanticConventions.Service.name.rawValue: AttributeValue.string("opbeans-swift")
    ])

    let registration = AppMetricsMeterProvider.register(metricExporter: exporter, resource: resource)
    var histogram = registration.meter.histogramBuilder(name: "application.launch.time").build()
    histogram.record(value: 1.0)

    MetricKitMetricExportSession.prepareExportForMetricKitPayload(
      start: Date(timeIntervalSince1970: 100),
      end: Date(timeIntervalSince1970: 200)
    )
    MetricKitMetricExportSession.flushMetricKitExport()

    XCTAssertEqual(exporter.exported.count, 1)
    let serviceName = exporter.exported[0][0].resource.attributes[SemanticConventions.Service.name.rawValue]
    guard case let .string(value) = serviceName else {
      return XCTFail("expected string service.name")
    }
    XCTAssertEqual(value, "opbeans-swift")
  }

  func testMetricKitTriggeredMetricReaderStampsMetricKitWindowOnExport() {
    let inner = CapturingMetricExporter()
    let sut = MetricKitTriggeredMetricReader(exporter: inner)
    let producer = StubMetricProducer()
    let point = LongPointData(
      startEpochNanos: 10,
      endEpochNanos: 20,
      attributes: [:],
      exemplars: [],
      value: 3
    )
    producer.metrics = [
      MetricData.createLongSum(
        resource: Resource.empty,
        instrumentationScopeInfo: InstrumentationScopeInfo(name: AppMetricsMeter.scopeName),
        name: "application.exits",
        description: "",
        unit: "",
        isMonotonic: false,
        data: SumData(aggregationTemporality: .delta, points: [point])
      )
    ]
    sut.register(registration: producer)

    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let end = Date(timeIntervalSince1970: 1_700_008_640)
    sut.setPendingExportWindow(start: start, end: end)

    XCTAssertEqual(sut.forceFlush(), .success)
    XCTAssertEqual(inner.exported.count, 1)
    let exportedPoint = inner.exported[0][0].data.points[0] as! LongPointData
    XCTAssertEqual(exportedPoint.startEpochNanos, UInt64(start.timeIntervalSince1970 * 1_000_000_000))
    XCTAssertEqual(exportedPoint.endEpochNanos, UInt64(end.timeIntervalSince1970 * 1_000_000_000))
  }

  func testMetricKitTriggeredMetricReaderFailsExportWithoutPendingWindow() {
    let inner = CapturingMetricExporter()
    let sut = MetricKitTriggeredMetricReader(exporter: inner)
    let producer = StubMetricProducer()
    producer.metrics = [
      MetricData.createLongSum(
        resource: Resource.empty,
        instrumentationScopeInfo: InstrumentationScopeInfo(name: AppMetricsMeter.scopeName),
        name: "application.exits",
        description: "",
        unit: "",
        isMonotonic: false,
        data: SumData(
          aggregationTemporality: .delta,
          points: [
            LongPointData(
              startEpochNanos: 1,
              endEpochNanos: 2,
              attributes: [:],
              exemplars: [],
              value: 1
            )
          ]
        )
      )
    ]
    sut.register(registration: producer)

    XCTAssertEqual(sut.forceFlush(), .failure)
    XCTAssertTrue(inner.exported.isEmpty)
  }

  func testMetricKitWindowMetricExporterRewritesPointTimes() {
    let inner = CapturingMetricExporter()
    let sut = MetricKitWindowMetricExporter(inner: inner)

    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let end = Date(timeIntervalSince1970: 1_700_008_640)
    sut.setPendingWindow(start: start, end: end)

    let point = HistogramPointData(
      startEpochNanos: 10,
      endEpochNanos: 20,
      attributes: [:],
      exemplars: [],
      sum: 1,
      count: 1,
      min: 1,
      max: 1,
      boundaries: [],
      counts: [],
      hasMin: true,
      hasMax: true
    )
    let metric = MetricData.createHistogram(
      resource: Resource.empty,
      instrumentationScopeInfo: InstrumentationScopeInfo(name: AppMetricsMeter.scopeName),
      name: "application.launch.time",
      description: "",
      unit: "s",
      data: HistogramData(aggregationTemporality: .delta, points: [point])
    )

    XCTAssertEqual(sut.export(metrics: [metric]), .success)
    XCTAssertEqual(inner.exported.count, 1)
    let exportedPoint = inner.exported[0][0].getHistogramData()[0]
    XCTAssertEqual(exportedPoint.startEpochNanos, UInt64(start.timeIntervalSince1970 * 1_000_000_000))
    XCTAssertEqual(exportedPoint.endEpochNanos, UInt64(end.timeIntervalSince1970 * 1_000_000_000))
  }
}
