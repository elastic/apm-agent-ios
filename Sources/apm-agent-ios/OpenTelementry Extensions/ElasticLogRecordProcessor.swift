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



public struct ElasticLogRecordProcessor : LogRecordProcessor {
    var processor : BatchLogRecordProcessor
    internal init(logRecordExporter: LogRecordExporter, scheduleDelay: TimeInterval = 5, exportTimeout: TimeInterval = 30, maxQueueSize: Int = 2048, maxExportBatchSize: Int = 512, willExportCallback: ((inout [ReadableLogRecord])->Void)? = nil) {
        processor = BatchLogRecordProcessor(logRecordExporter: logRecordExporter, scheduleDelay: scheduleDelay, exportTimeout: exportTimeout, maxQueueSize: maxQueueSize, maxExportBatchSize: maxExportBatchSize, willExportCallback: willExportCallback)
    }
    
    public func onEmit(logRecord: OpenTelemetrySdk.ReadableLogRecord) {
        guard CentralConfig().data.recording else {
            return
        }
                
        var attributes = logRecord.attributes
        attributes[ElasticAttributes.sessionId.rawValue] = AttributeValue.string(SessionManager.instance.session())
        processor.onEmit(logRecord:ReadableLogRecord(resource: logRecord.resource,
                          instrumentationScopeInfo: logRecord.instrumentationScopeInfo,
                          timestamp: logRecord.timestamp,
                          observedTimestamp: logRecord.observedTimestamp,
                          spanContext: logRecord.spanContext,
                          severity: logRecord.severity,
                          body: logRecord.body,
                          attributes: attributes))
                        
  
    }
    
    public func forceFlush() -> OpenTelemetrySdk.ExportResult {
        processor.forceFlush()
    }
    
    public func shutdown() -> OpenTelemetrySdk.ExportResult {
        processor.shutdown()
    }
    
    
}
