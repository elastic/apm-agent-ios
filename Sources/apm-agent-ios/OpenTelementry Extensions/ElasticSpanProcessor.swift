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
import NetworkStatus
import OpenTelemetryApi
import OpenTelemetrySdk
import os.log

public struct ElasticSpanProcessor: SpanProcessor {
  var processor: SpanProcessor
  var exporter: SpanExporter
  var filters = [SignalFilter<ReadableSpan>]()
  public let isStartRequired: Bool
  public let isEndRequired: Bool

  static var netstatInjector: NetworkStatusInjector? = { () -> NetworkStatusInjector? in
    do {
      let netstats = try NetworkStatus()
      return NetworkStatusInjector(netstat: netstats)
    } catch {
      if #available(iOS 14, macOS 11, tvOS 14, *) {
        os_log(
          .error, "failed to initialize network connection status: %@", error.localizedDescription)
      } else {
        NSLog("failed to initialize network connection status: %@", error.localizedDescription)
      }
      return nil
    }
  }()

  public init(
    spanExporter: SpanExporter,
    _ filters: [SignalFilter<ReadableSpan>] = [SignalFilter<ReadableSpan>](),
    scheduleDelay: TimeInterval = 5, exportTimeout: TimeInterval = 30,
    maxQueueSize: Int = 2048, maxExportBatchSize: Int = 512,
    willExportCallback: ((inout [SpanData]) -> Void)? = nil
  ) {
    processor = BatchSpanProcessor(
      spanExporter: spanExporter, scheduleDelay: scheduleDelay, exportTimeout: exportTimeout,
      maxQueueSize: maxQueueSize, maxExportBatchSize: maxExportBatchSize,
      willExportCallback: willExportCallback)
    isStartRequired = processor.isStartRequired
    isEndRequired = processor.isEndRequired
    exporter = spanExporter
    self.filters = filters
  }

  public func onStart(
    parentContext: OpenTelemetryApi.SpanContext?, span: OpenTelemetrySdk.ReadableSpan
  ) {
    span.setAttribute(
      key: ElasticAttributes.sessionId.rawValue,
      value: AttributeValue.string(SessionManager.instance.session()))
    if let networkStatusInjector = Self.netstatInjector {
      networkStatusInjector.inject(span: span)
    }
    span.setAttribute(key: "type", value: AttributeValue.string("mobile"))
    processor.onStart(parentContext: parentContext, span: span)
  }

  public mutating func onEnd(span: OpenTelemetrySdk.ReadableSpan) {

    for filter in filters where !filter.shouldInclude(span) {
      return
    }

    if span.isHttpSpan() {
      var spanData = span.toSpanData()
      if spanData.parentSpanId == nil, let transactionSpan = span as? RecordEventsReadableSpan {

        var newAttributes = AttributesDictionary(capacity: spanData.attributes.count)
        newAttributes.updateValue(value: AttributeValue.string("mobile"), forKey: "type")
        newAttributes.updateValue(
          value: AttributeValue.string(SessionManager.instance.session()),
          forKey: ElasticAttributes.sessionId.rawValue)
        let parentSpanContext = SpanContext.create(
          traceId: span.context.traceId, spanId: SpanId.random(), traceFlags: TraceFlags(),
          traceState: TraceState())

        let parentSpan = RecordEventsReadableSpan.startSpan(
          context: parentSpanContext,
          name: spanData.name,
          instrumentationScopeInfo: span.instrumentationScopeInfo,
          kind: span.kind,
          parentContext: nil,
          hasRemoteParent: false,
          spanLimits: transactionSpan.spanLimits,
          spanProcessor: NoopSpanProcessor(),
          clock: transactionSpan.clock,
          resource: transactionSpan.resource,
          attributes: newAttributes,
          links: transactionSpan.links,
          totalRecordedLinks: transactionSpan.totalRecordedLinks,
          startTime: transactionSpan.startTime)

        parentSpan.end(time: transactionSpan.endTime!)

        spanData.settingParentSpanId(parentSpanContext.spanId)

       _ = exporter.export(spans: [spanData, parentSpan.toSpanData()])

        return
      }
    }
    processor.onEnd(span: span)
  }

  public mutating func shutdown(explicitTimeout: TimeInterval? = nil) {
    processor.shutdown(explicitTimeout: explicitTimeout)
  }

  public func forceFlush(timeout: TimeInterval?) {
    processor.forceFlush(timeout: timeout)
  }

}

internal struct NoopSpanProcessor: SpanProcessor {
  init() {}

  let isStartRequired = false
  let isEndRequired = false

  func onStart(parentContext: SpanContext?, span: ReadableSpan) {}

  func onEnd(span: ReadableSpan) {}

  func shutdown(explicitTimeout: TimeInterval? = nil) {}

  func forceFlush(timeout: TimeInterval? = nil) {}
}
