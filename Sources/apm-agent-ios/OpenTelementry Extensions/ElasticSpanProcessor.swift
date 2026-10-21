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
  var filters = [SignalFilter<any ReadableSpan>]()
  var attributeInterceptor: AnyInterceptor<[String: AttributeValue]>
  public let isStartRequired: Bool
  public let isEndRequired: Bool

#if os(iOS) && !targetEnvironment(macCatalyst)

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

#endif // os(iOS) && !targetEnvironment(macCatalyst)

  public init(
    spanExporter: SpanExporter,
    agentConfiguration: AgentConfiguration,
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
    self.filters = agentConfiguration.spanFilters
    self.attributeInterceptor = agentConfiguration.spanAttributeInterceptor
      .join { attributes in
        var newAttributes = attributes
        newAttributes["type"] =  .string("mobile")
        return newAttributes
      }
      .join { attributes in
        var newAttributes = attributes
        newAttributes[SemanticConventions.Session.id.rawValue] = .string(
          SessionManager.instance.session())
        return newAttributes
      }
  }

  public func onStart(
    parentContext: OpenTelemetryApi.SpanContext?, span: OpenTelemetrySdk.ReadableSpan
  ) {

    span.setAttributes(attributeInterceptor.intercept(span.getAttributes()))

    #if os(iOS) && !targetEnvironment(macCatalyst)
    if span.isHttpSpan(), let networkStatusInjector = Self.netstatInjector {
      networkStatusInjector.inject(span: span)
    } else {
      span
        .setAttribute(key: SemanticConventions.Network.connectionType.rawValue,
                      value: .string(NetworkStatusManager().status()))
    }
    #endif
    processor.onStart(parentContext: parentContext, span: span)
  }

  public mutating func onEnd(span: OpenTelemetrySdk.ReadableSpan) {

    for filter in filters where !filter.shouldInclude(span) {
      return
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
