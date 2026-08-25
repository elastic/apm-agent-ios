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

import Foundation
import OpenTelemetrySdk

public final class WaitingSpanExporter: SpanExporter, @unchecked Sendable {
  private var spanDataList = [SpanData]()
  private let condition = NSCondition()
  private let numberToWaitFor: Int
  public private(set) var shutdownCalled = false

  public init(numberToWaitFor: Int) {
    self.numberToWaitFor = numberToWaitFor
  }

  public func waitForExport(timeout: TimeInterval = 10) -> [SpanData]? {
    condition.lock()
    defer { condition.unlock() }

    let deadline = Date().addingTimeInterval(timeout)
    while spanDataList.count < numberToWaitFor {
      guard condition.wait(until: deadline) else {
        return nil
      }
    }
    let exported = spanDataList
    spanDataList.removeAll()
    return exported
  }

  public func export(
    spans: [SpanData],
    explicitTimeout: TimeInterval? = nil
  ) -> SpanExporterResultCode {
    condition.lock()
    spanDataList.append(contentsOf: spans)
    condition.broadcast()
    condition.unlock()
    return .success
  }

  public func flush(explicitTimeout: TimeInterval? = nil) -> SpanExporterResultCode {
    .success
  }

  public func shutdown(explicitTimeout: TimeInterval? = nil) {
    shutdownCalled = true
  }
}

public final class WaitingLogRecordExporter: LogRecordExporter, @unchecked Sendable {
  private var logRecordList = [ReadableLogRecord]()
  private let condition = NSCondition()
  private let numberToWaitFor: Int
  public private(set) var shutdownCalled = false

  public init(numberToWaitFor: Int) {
    self.numberToWaitFor = numberToWaitFor
  }

  public func waitForExport(timeout: TimeInterval = 10) -> [ReadableLogRecord]? {
    condition.lock()
    defer { condition.unlock() }

    let deadline = Date().addingTimeInterval(timeout)
    while logRecordList.count < numberToWaitFor {
      guard condition.wait(until: deadline) else {
        return nil
      }
    }
    let exported = logRecordList
    logRecordList.removeAll()
    return exported
  }

  public func export(
    logRecords: [ReadableLogRecord],
    explicitTimeout: TimeInterval? = nil
  ) -> ExportResult {
    condition.lock()
    logRecordList.append(contentsOf: logRecords)
    condition.broadcast()
    condition.unlock()
    return .success
  }

  public func forceFlush(explicitTimeout: TimeInterval? = nil) -> ExportResult {
    .success
  }

  public func shutdown(explicitTimeout: TimeInterval? = nil) {
    shutdownCalled = true
  }
}

public final class WaitingMetricExporter: MetricExporter {
  private var metricDataList = [MetricData]()
  private let condition = NSCondition()
  private let numberToWaitFor: Int
  public private(set) var shutdownCalled = false

  public init(numberToWaitFor: Int) {
    self.numberToWaitFor = numberToWaitFor
  }

  public func waitForExport(timeout: TimeInterval = 10) -> [MetricData]? {
    condition.lock()
    defer { condition.unlock() }

    let deadline = Date().addingTimeInterval(timeout)
    while metricDataList.count < numberToWaitFor {
      guard condition.wait(until: deadline) else {
        return nil
      }
    }
    let exported = metricDataList
    metricDataList.removeAll()
    return exported
  }

  public func export(metrics: [MetricData]) -> ExportResult {
    condition.lock()
    metricDataList.append(contentsOf: metrics)
    condition.broadcast()
    condition.unlock()
    return .success
  }

  public func flush() -> ExportResult {
    .success
  }

  public func shutdown() -> ExportResult {
    shutdownCalled = true
    return .success
  }

  public func getAggregationTemporality(
    for instrument: InstrumentType
  ) -> AggregationTemporality {
    .cumulative
  }
}
