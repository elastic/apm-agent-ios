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
import os

/// Collects and exports only metrics from the Application Metrics instrumentation scope, on demand
/// (driven by MetricKit delivery instead of a fixed interval).
///
/// Each export stamps collected points with the pending ``MetricKitReportingWindow`` from the
/// corresponding ``MXMetricPayload`` before calling the exporter.
final class MetricKitTriggeredMetricReader: MetricReader {
  private static let log = OSLog(subsystem: "co.elastic.elasticApm", category: "MetricKit")

  private let lock = NSLock()
  private let exporter: MetricExporter
  private var producer: MetricProducer?
  private var pendingWindow: MetricKitReportingWindow?

  init(exporter: MetricExporter) {
    self.exporter = exporter
  }

  func register(registration: CollectionRegistration) {
    producer = registration as? MetricProducer
  }

  /// Sets the MetricKit reporting window for the next ``forceFlush()`` (from ``MXMetricPayload`` timestamps).
  func setPendingExportWindow(start: Date, end: Date) {
    lock.lock()
    pendingWindow = MetricKitReportingWindow(start: start, end: end)
    lock.unlock()
  }

  func forceFlush() -> ExportResult {
    guard let producer else { return .success }
    var metrics = producer.collectAllMetrics()
    if metrics.isEmpty {
      return .success
    }

    lock.lock()
    let window = pendingWindow
    pendingWindow = nil
    lock.unlock()

    guard let window else {
      return .failure
    }

    metrics = Self.stripExemplars(MetricKitReportingWindow.stamp(metrics, window: window))
    let result = exporter.export(metrics: metrics)
    if result == .failure {
      os_log(.error, log: Self.log, "MetricKit metric export failed")
    }
    return result
  }

  /// MetricKit replay records one sample per bucket count; exemplars with empty trace IDs break ES otel export.
  private static func stripExemplars(_ metrics: [MetricData]) -> [MetricData] {
    for metric in metrics {
      for point in metric.data.points {
        point.exemplars = []
      }
    }
    return metrics
  }

  func shutdown() -> ExportResult {
    producer = nil
    return exporter.shutdown()
  }

  func getAggregationTemporality(for instrument: InstrumentType) -> AggregationTemporality {
    // Elasticsearch otel-native metrics require delta histograms.
    switch instrument {
    case .histogram:
      return .delta
    default:
      return exporter.getAggregationTemporality(for: instrument)
    }
  }

  func getDefaultAggregation(for instrument: InstrumentType) -> Aggregation {
    exporter.getDefaultAggregation(for: instrument)
  }
}
