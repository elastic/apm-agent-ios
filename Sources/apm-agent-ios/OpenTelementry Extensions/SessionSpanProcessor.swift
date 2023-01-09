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

public struct SessionSpanProcessor : SpanProcessor {
    var processor : SpanProcessor

    public let isStartRequired: Bool
    public let isEndRequired: Bool
    
    
    public init(spanExporter: SpanExporter, scheduleDelay: TimeInterval = 5, exportTimeout: TimeInterval = 30,
                maxQueueSize: Int = 2048, maxExportBatchSize: Int = 512, willExportCallback: ((inout [SpanData]) -> Void)? = nil) {
        processor = BatchSpanProcessor(spanExporter: spanExporter, scheduleDelay: scheduleDelay, exportTimeout: exportTimeout, maxQueueSize: maxQueueSize, maxExportBatchSize: maxExportBatchSize, willExportCallback: willExportCallback)
        isStartRequired = processor.isStartRequired
        isEndRequired = processor.isEndRequired
    }
    
    init(processor: SpanProcessor) {
        self.processor = processor
        isStartRequired = processor.isStartRequired
        isEndRequired = processor.isEndRequired
    }
    
    public func onStart(parentContext: OpenTelemetryApi.SpanContext?, span: OpenTelemetrySdk.ReadableSpan) {
        span.setAttribute(key: ElasticAttributes.sessionId.rawValue, value: AttributeValue.string(SessionManager.instance.session()))
        processor.onStart(parentContext: parentContext, span: span)
    }
    
    public mutating func onEnd(span: OpenTelemetrySdk.ReadableSpan) {
        processor.onEnd(span: span)
    }
    
    public mutating func shutdown() {
        processor.shutdown()
    }
    
    public func forceFlush(timeout: TimeInterval?) {
        processor.forceFlush(timeout: timeout)
    }
    
}
