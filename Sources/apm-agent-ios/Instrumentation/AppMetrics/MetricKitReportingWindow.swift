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

/// ``MXMetricPayload.timeStampBegin`` / ``timeStampEnd`` converted for OTLP point timestamps.
struct MetricKitReportingWindow: Equatable {
  let startEpochNanos: UInt64
  let endEpochNanos: UInt64

  init(start: Date, end: Date) {
    startEpochNanos = start.timeIntervalSince1970.toNanoseconds
    endEpochNanos = end.timeIntervalSince1970.toNanoseconds
  }

  /// Rewrites every exported point's ``PointData.startEpochNanos`` / ``endEpochNanos`` to this window.
  static func stamp(_ metrics: [MetricData], window: MetricKitReportingWindow) -> [MetricData] {
    for metric in metrics {
      for point in metric.data.points {
        point.startEpochNanos = window.startEpochNanos
        point.endEpochNanos = window.endEpochNanos
      }
    }
    return metrics
  }
}
