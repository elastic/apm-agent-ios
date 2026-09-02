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

import ElasticApmTestSupport
import Foundation
import NIO
import OpenTelemetryApi
import OpenTelemetryProtocolExporterCommon
import OpenTelemetrySdk
import PersistenceExporter
import XCTest

@testable import ElasticApm

final class MetricTemporalityTests: XCTestCase {
  func testGrpcExporterProducesDeltaPreferredMetricData() throws {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let channel = OpenTelemetryHelper.makeChannel(
      target: try XCTUnwrap(GrpcChannelTarget(endpoint: URL(string: "http://localhost:4317")!)),
      group: group)
    let exporter = OpenTelemetryInitializer.makeGrpcMetricExporter(
      channel: channel, config: OtlpConfiguration())
    defer {
      XCTAssertEqual(exporter.shutdown(), .success)
      XCTAssertNoThrow(try group.syncShutdownGracefully())
    }

    try assertExportedMetricTemporalities(from: exporter)
  }

  func testHttpExporterProducesDeltaPreferredMetricData() throws {
    let exporter = OpenTelemetryInitializer.makeHttpMetricExporter(
      endpoint: URL(string: "http://localhost:4318/v1/metrics")!,
      config: OtlpConfiguration())
    defer {
      XCTAssertEqual(exporter.shutdown(), .success)
    }

    try assertExportedMetricTemporalities(from: exporter)
  }

  func testPersistenceDecoratorPreservesDeltaPreferredTemporality() throws {
    let storageURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("metric-temporality-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: storageURL, withIntermediateDirectories: true)
    defer {
      XCTAssertNoThrow(try FileManager.default.removeItem(at: storageURL))
    }

    let exporter = OpenTelemetryInitializer.makeHttpMetricExporter(
      endpoint: URL(string: "http://localhost:4318/v1/metrics")!,
      config: OtlpConfiguration())
    let decoratedExporter = try PersistenceMetricExporterDecorator(
      metricExporter: exporter,
      storageURL: storageURL,
      exportCondition: { false })
    defer {
      XCTAssertEqual(decoratedExporter.shutdown(), .success)
    }

    assertDeltaPreferredMapping(on: decoratedExporter)
  }

  private func assertExportedMetricTemporalities(
    from exporter: MetricExporter,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    let collectingExporter = WaitingMetricExporter(
      numberToWaitFor: 1,
      aggregationTemporalitySelector: AggregationTemporalitySelector {
        exporter.getAggregationTemporality(for: $0)
      })
    let provider = MeterProviderSdk.builder()
      .registerView(
        selector: InstrumentSelector.builder()
          .setInstrument(name: ".*")
          .build(),
        view: View.builder().build()
      )
      .registerMetricReader(
        reader: PeriodicMetricReaderBuilder(exporter: collectingExporter).build()
      )
      .build()
    let meter = provider.get(name: "MetricTemporalityTests")

    let counter = meter.counterBuilder(name: "temporality.counter").build()
    counter.add(value: 1)

    let observableCounter = meter.counterBuilder(name: "temporality.observable-counter")
      .buildWithCallback { measurement in
        measurement.record(value: 2)
      }

    let histogram = meter.histogramBuilder(name: "temporality.histogram").build()
    histogram.record(value: 3)

    let upDownCounter = meter.upDownCounterBuilder(name: "temporality.up-down-counter").build()
    upDownCounter.add(value: 4)

    let observableUpDownCounter = meter
      .upDownCounterBuilder(name: "temporality.observable-up-down-counter")
      .buildWithCallback { measurement in
        measurement.record(value: 5)
      }

    let exportedMetrics = try withExtendedLifetime(observableCounter) {
      try withExtendedLifetime(observableUpDownCounter) {
        XCTAssertEqual(provider.forceFlush(), .success, file: file, line: line)
        return try XCTUnwrap(
          collectingExporter.waitForExport(),
          "Expected all instrument types to be exported",
          file: file,
          line: line)
      }
    }
    XCTAssertEqual(provider.shutdown(), .success, file: file, line: line)

    let temporalities = Dictionary(
      uniqueKeysWithValues: exportedMetrics.map {
        ($0.name, $0.data.aggregationTemporality)
      })
    XCTAssertEqual(temporalities["temporality.counter"], .delta, file: file, line: line)
    XCTAssertEqual(
      temporalities["temporality.observable-counter"], .delta, file: file, line: line)
    XCTAssertEqual(temporalities["temporality.histogram"], .delta, file: file, line: line)
    XCTAssertEqual(
      temporalities["temporality.up-down-counter"], .cumulative, file: file, line: line)
    XCTAssertEqual(
      temporalities["temporality.observable-up-down-counter"],
      .cumulative,
      file: file,
      line: line)
  }

  private func assertDeltaPreferredMapping(
    on exporter: MetricExporter,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(
      exporter.getAggregationTemporality(for: .counter), .delta, file: file, line: line)
    XCTAssertEqual(
      exporter.getAggregationTemporality(for: .observableCounter),
      .delta,
      file: file,
      line: line)
    XCTAssertEqual(
      exporter.getAggregationTemporality(for: .histogram), .delta, file: file, line: line)
    XCTAssertEqual(
      exporter.getAggregationTemporality(for: .upDownCounter),
      .cumulative,
      file: file,
      line: line)
    XCTAssertEqual(
      exporter.getAggregationTemporality(for: .observableUpDownCounter),
      .cumulative,
      file: file,
      line: line)
  }
}
