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

/// Rewrites ``PointData.startEpochNanos`` / ``endEpochNanos`` to a pending MetricKit payload window
/// for the next export (then clears the window).
final class MetricKitWindowMetricExporter: MetricExporter {
  private let lock = NSLock()
  private var pendingWindow: MetricKitReportingWindow?
  private let inner: MetricExporter

  init(inner: MetricExporter) {
    self.inner = inner
  }

  /// Set the reporting window for the next ``export(metrics:)`` call (e.g. from ``MXMetricPayload`` timestamps).
  func setPendingWindow(start: Date, end: Date) {
    lock.lock()
    pendingWindow = MetricKitReportingWindow(start: start, end: end)
    lock.unlock()
  }

  func export(metrics: [MetricData]) -> ExportResult {
    lock.lock()
    let window = pendingWindow
    if window != nil {
      pendingWindow = nil
    }
    lock.unlock()

    let toSend = if let window {
      MetricKitReportingWindow.stamp(metrics, window: window)
    } else {
      metrics
    }
    return inner.export(metrics: toSend)
  }

  func flush() -> ExportResult {
    inner.flush()
  }

  func shutdown() -> ExportResult {
    inner.shutdown()
  }

  func getAggregationTemporality(for instrument: InstrumentType) -> AggregationTemporality {
    inner.getAggregationTemporality(for: instrument)
  }

  func getDefaultAggregation(for instrument: InstrumentType) -> Aggregation {
    inner.getDefaultAggregation(for: instrument)
  }
}
