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
import OpenTelemetrySdk
import XCTest
@testable import ElasticApm

private final class RaceDetectingMetricExporter: MetricExporter {
  private let lock = NSLock()
  private var inFlight = false
  private(set) var detectedRaces = 0

  func export(metrics: [MetricData]) -> ExportResult {
    lock.lock()
    if inFlight {
      detectedRaces += 1
    }
    inFlight = true
    lock.unlock()

    Thread.sleep(forTimeInterval: 0.002)

    lock.lock()
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

final class SynchronizedMetricExporterTests: XCTestCase {
  func testSynchronizedMetricExporterSerializesConcurrentExportCalls() {
    let inner = RaceDetectingMetricExporter()
    let sut = SynchronizedMetricExporter(inner: inner)

    DispatchQueue.concurrentPerform(iterations: 100) { _ in
      _ = sut.export(metrics: [])
    }

    XCTAssertEqual(inner.detectedRaces, 0)
  }

  func testSynchronizedMetricExporterSerializesConcurrentFlushAndExport() {
    let inner = RaceDetectingMetricExporter()
    let sut = SynchronizedMetricExporter(inner: inner)

    DispatchQueue.concurrentPerform(iterations: 100) { index in
      if index.isMultiple(of: 2) {
        _ = sut.export(metrics: [])
      } else {
        _ = sut.flush()
      }
    }

    XCTAssertEqual(inner.detectedRaces, 0)
  }
}
