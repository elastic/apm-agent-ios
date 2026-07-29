// Copyright © 2022 Elasticsearch BV
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation

/// Pure helpers backing ``AppMetrics`` so histogram/counter semantics stay testable without MetricKit payloads.
enum AppMetricsRecordingSupport {
  struct HistogramBucketEdge {
    var startSeconds: Double
    var endSeconds: Double
    var count: Int
  }

  /// Expands each MetricKit histogram bucket into `count` samples at its midpoint (`(start + end) / 2`).
  /// Skips negative midpoints or non-positive counts.
  static func histogramSampleValues(secondsFromBuckets buckets: [HistogramBucketEdge]) -> [Double] {
    var values: [Double] = []
    for bucket in buckets {
      let midpoint = (bucket.startSeconds + bucket.endSeconds) / 2
      guard midpoint >= 0, bucket.count > 0 else { continue }
      for _ in 0 ..< bucket.count {
        values.append(midpoint)
      }
    }
    return values
  }

  /// Filters exit-type aggregates to strictly positive deltas before applying to OTLP sums.
  static func nonZeroExitSums(byExitType sums: [(typeRawValue: String, sum: Int)]) -> [(typeRawValue: String, sum: Int)] {
    sums.filter { $0.sum > 0 }
  }
}
