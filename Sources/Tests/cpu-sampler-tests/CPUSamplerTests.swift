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
import OpenTelemetryApi
import OpenTelemetrySdk
import XCTest

@testable import CPUSampler

final class CPUSamplerTests: XCTestCase {
  private let percentSum =
    Double(ProcessInfo.processInfo.activeProcessorCount) * 50.0

  func testDefaultMetricUsesProcessRatioWithoutLegacyState() throws {
    let metric = try collectMetric(useLegacyAttributeNames: false)
    let point = try XCTUnwrap(metric.data.points.first as? DoublePointData)

    XCTAssertEqual(metric.name, "process.cpu.utilization")
    XCTAssertNotEqual(metric.name, "system.cpu.usage")
    XCTAssertEqual(point.value, 0.5, accuracy: 0.000_001)
    XCTAssertGreaterThanOrEqual(point.value, 0)
    XCTAssertLessThanOrEqual(point.value, 1)
    XCTAssertTrue(point.attributes.isEmpty)
    XCTAssertNil(point.attributes["state"])
  }

  func testLegacyMetricRestoresPercentSumNameAndState() throws {
    let metric = try collectMetric(useLegacyAttributeNames: true)
    let point = try XCTUnwrap(metric.data.points.first as? DoublePointData)

    XCTAssertEqual(metric.name, "system.cpu.usage")
    XCTAssertNotEqual(metric.name, "process.cpu.utilization")
    XCTAssertEqual(point.value, percentSum, accuracy: 0.000_001)
    XCTAssertGreaterThan(point.value, 1)
    XCTAssertEqual(point.attributes, ["state": .string("app")])
  }

  private func collectMetric(useLegacyAttributeNames: Bool) throws -> MetricData {
    let exporter = WaitingMetricExporter(numberToWaitFor: 1)
    let provider = MeterProviderSdk.builder()
      .registerView(
        selector: InstrumentSelector.builder()
          .setInstrument(name: ".*")
          .build(),
        view: View.builder().build()
      )
      .registerMetricReader(
        reader: PeriodicMetricReaderBuilder(exporter: exporter).build()
      )
      .build()
    OpenTelemetry.registerMeterProvider(meterProvider: provider)

    let sampler = CPUSampler(
      useLegacyAttributeNames: useLegacyAttributeNames,
      cpuFootprint: { self.percentSum }
    )
    let metric = try withExtendedLifetime(sampler) {
      XCTAssertEqual(provider.forceFlush(), .success)
      return try XCTUnwrap(exporter.waitForExport()?.first)
    }
    XCTAssertEqual(provider.shutdown(), .success)
    return metric
  }
}
