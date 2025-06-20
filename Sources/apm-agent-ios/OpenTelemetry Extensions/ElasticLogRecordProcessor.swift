// Copyright © 2023 Elasticsearch BV
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
import OpenTelemetryApi
import OpenTelemetrySdk

public struct ElasticLogRecordProcessor: LogRecordProcessor {
  var processor: BatchLogRecordProcessor
  var filters = [SignalFilter<MutableLogRecord>]()
  internal init(
    logRecordExporter: LogRecordExporter,
    _ filters: [SignalFilter<MutableLogRecord>] = [SignalFilter<MutableLogRecord>](),
    scheduleDelay: TimeInterval = 5, exportTimeout: TimeInterval = 30, maxQueueSize: Int = 2048,
    maxExportBatchSize: Int = 512, willExportCallback: ((inout [ReadableLogRecord]) -> Void)? = nil
  ) {
    self.filters = filters
    processor = BatchLogRecordProcessor(
      logRecordExporter: logRecordExporter, scheduleDelay: scheduleDelay,
      exportTimeout: exportTimeout, maxQueueSize: maxQueueSize,
      maxExportBatchSize: maxExportBatchSize, willExportCallback: willExportCallback)
  }

  public func onEmit(logRecord: OpenTelemetrySdk.ReadableLogRecord) {
    guard CentralConfig().data.recording else {
      return
    }

    var attributes = logRecord.attributes
    attributes[ElasticAttributes.sessionId.rawValue] = AttributeValue.string(
      SessionManager.instance.session())
    #if os(iOS) && !targetEnvironment(macCatalyst)
      attributes[SemanticAttributes.networkConnectionType.rawValue] = AttributeValue
        .string(NetworkStatusManager().status())
    #endif // os(iOS) && !targetEnvironment(macCatalyst)


    var appendedLogRecord = MutableLogRecord(from: logRecord)
    appendedLogRecord.attributes.merge(attributes) { (_, new) in new }


    for filter in filters where !filter.shouldInclude(&appendedLogRecord) {
        return
      }

    processor.onEmit(logRecord: appendedLogRecord.finish())

  }

  public func forceFlush(explicitTimeout: TimeInterval? = nil) -> OpenTelemetrySdk.ExportResult {
    processor.forceFlush(explicitTimeout: explicitTimeout)
  }

  public func shutdown(explicitTimeout: TimeInterval? = nil) -> OpenTelemetrySdk.ExportResult {
    processor.shutdown(explicitTimeout: explicitTimeout)
  }

}
