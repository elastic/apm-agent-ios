// Copyright © 2021 Elasticsearch BV
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
import OpenTelemetryApi
import OpenTelemetrySdk
import XCTest

@testable import MemorySampler

final class MemorySamplerTests: XCTestCase {
  func testDefaultMetricUsesProcessNameWithoutLegacyState() throws {
    let metric = try collectMetric(useLegacyAttributeNames: false)
    let point = try XCTUnwrap(metric.data.points.first as? DoublePointData)

    XCTAssertEqual(metric.name, "process.memory.usage")
    XCTAssertNotEqual(metric.name, "system.memory.usage")
    XCTAssertEqual(point.value, 4_096)
    XCTAssertEqual(metric.unit, "By")
    guard case .DoubleSum = metric.type else {
      return XCTFail("process.memory.usage must use an UpDownCounter")
    }
    XCTAssertFalse(metric.isMonotonic)
    XCTAssertTrue(point.attributes.isEmpty)
    XCTAssertNil(point.attributes["state"])
  }

  func testLegacyMetricRestoresSystemNameAndState() throws {
    let metric = try collectMetric(useLegacyAttributeNames: true)
    let point = try XCTUnwrap(metric.data.points.first as? DoublePointData)

    XCTAssertEqual(metric.name, "system.memory.usage")
    XCTAssertNotEqual(metric.name, "process.memory.usage")
    XCTAssertEqual(point.value, 4_096)
    XCTAssertEqual(metric.unit, "")
    guard case .DoubleGauge = metric.type else {
      return XCTFail("Legacy system.memory.usage must remain a gauge")
    }
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

    let sampler = MemorySampler(
      useLegacyAttributeNames: useLegacyAttributeNames,
      memoryFootprint: { 4_096 }
    )
    let metric = try withExtendedLifetime(sampler) {
      XCTAssertEqual(provider.forceFlush(), .success)
      return try XCTUnwrap(exporter.waitForExport()?.first)
    }
    XCTAssertEqual(provider.shutdown(), .success)
    return metric
  }
}
