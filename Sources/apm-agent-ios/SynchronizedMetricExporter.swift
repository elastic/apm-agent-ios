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

/// Serializes ``MetricExporter`` calls so a single instance can be shared safely by the global
/// periodic meter provider and the MetricKit ``ApplicationMetricsMeterProvider``.
final class SynchronizedMetricExporter: MetricExporter {
  private let lock = NSLock()
  private let inner: MetricExporter

  init(inner: MetricExporter) {
    self.inner = inner
  }

  func export(metrics: [MetricData]) -> ExportResult {
    lock.lock()
    defer { lock.unlock() }
    return inner.export(metrics: metrics)
  }

  func flush() -> ExportResult {
    lock.lock()
    defer { lock.unlock() }
    return inner.flush()
  }

  func shutdown() -> ExportResult {
    lock.lock()
    defer { lock.unlock() }
    return inner.shutdown()
  }

  func getAggregationTemporality(for instrument: InstrumentType) -> AggregationTemporality {
    inner.getAggregationTemporality(for: instrument)
  }

  func getDefaultAggregation(for instrument: InstrumentType) -> Aggregation {
    inner.getDefaultAggregation(for: instrument)
  }
}
