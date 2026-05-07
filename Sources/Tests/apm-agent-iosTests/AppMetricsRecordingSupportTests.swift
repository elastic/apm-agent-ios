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

@testable import ElasticApm
import XCTest

final class AppMetricsRecordingSupportTests: XCTestCase {
  func testHistogramSampleValuesRepeatsMidpointByBucketCount() {
    let buckets: [AppMetricsRecordingSupport.HistogramBucketEdge] = [
      AppMetricsRecordingSupport.HistogramBucketEdge(startSeconds: 0, endSeconds: 10, count: 2),
      AppMetricsRecordingSupport.HistogramBucketEdge(startSeconds: 10, endSeconds: 20, count: 1)
    ]
    let samples = AppMetricsRecordingSupport.histogramSampleValues(secondsFromBuckets: buckets)
    XCTAssertEqual(samples, [5, 5, 15])
  }

  func testHistogramSampleValuesOmitsBucketsWithNegativeMidpoint() {
    let buckets = [
      AppMetricsRecordingSupport.HistogramBucketEdge(startSeconds: -6, endSeconds: -2, count: 3),
      AppMetricsRecordingSupport.HistogramBucketEdge(startSeconds: 0, endSeconds: 4, count: 1)
    ]
    XCTAssertEqual(AppMetricsRecordingSupport.histogramSampleValues(secondsFromBuckets: buckets), [2])
  }

  func testHistogramSampleValuesOmitsNonPositiveCounts() {
    let buckets = [
      AppMetricsRecordingSupport.HistogramBucketEdge(startSeconds: 0, endSeconds: 2, count: 0),
      AppMetricsRecordingSupport.HistogramBucketEdge(startSeconds: 2, endSeconds: 4, count: 1)
    ]
    XCTAssertEqual(AppMetricsRecordingSupport.histogramSampleValues(secondsFromBuckets: buckets), [3])
  }

  func testHistogramSampleValuesMidpointUsesAverageOfEdges() {
    let buckets = [
      AppMetricsRecordingSupport.HistogramBucketEdge(startSeconds: 1, endSeconds: 5, count: 1)
    ]
    XCTAssertEqual(AppMetricsRecordingSupport.histogramSampleValues(secondsFromBuckets: buckets), [3])
  }

  func testNonZeroExitSumsDropsZerosAndKeepsOrdering() {
    let input: [(typeRawValue: String, sum: Int)] = [
      ("memoryResourceLimit", 0),
      ("watchdog", 2),
      ("badAccess", 0),
      ("normal", 1)
    ]
    let filtered = AppMetricsRecordingSupport.nonZeroExitSums(byExitType: input)
    XCTAssertEqual(filtered.count, 2)
    XCTAssertEqual(filtered[0].typeRawValue, "watchdog")
    XCTAssertEqual(filtered[0].sum, 2)
    XCTAssertEqual(filtered[1].typeRawValue, "normal")
    XCTAssertEqual(filtered[1].sum, 1)
  }
}
