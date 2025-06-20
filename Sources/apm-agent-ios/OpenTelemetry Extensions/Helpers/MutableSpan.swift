// Copyright © 2025 Elasticsearch BV
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

extension AttributesDictionary {
  func toDictonary() -> [String: AttributeValue] {
      return Dictionary(uniqueKeysWithValues: self.map { key, value in
      (key, value)
    })
  }
}

private extension SpanException {
  var eventAttributes: [String: AttributeValue] {
    [
      SemanticAttributes.exceptionType.rawValue: type,
      SemanticAttributes.exceptionMessage.rawValue: message,
      SemanticAttributes.exceptionStacktrace.rawValue: stackTrace?.joined(separator: "\n")
    ].compactMapValues { value in
      if let value, !value.isEmpty {
        return .string(value)
      }

      return nil
    }
  }
}

public class MutableSpan : ReadableSpan {
  private var span: RecordEventsReadableSpan
  public private(set) var attributes: AttributesDictionary
  public private(set) var events : ArrayWithCapacity<SpanData.Event>
  public private(set) var links: [SpanData.Link]
  public var totalRecordedLinks: Int
  public var totalAttributeCount: Int
  public var totalRecordedEvents: Int
  public var name: String


  public var hasEnded: Bool { get { span.hasEnded } }
  public var spanLimits: SpanLimits { get { span.spanLimits } }
  public var description: String { get { span.description }}
  public var context: SpanContext { get { span.context } }
  public var parentContext: SpanContext? { get { span.parentContext }}
  public var hasRemoteParent: Bool { get { span.hasRemoteParent }}
  public var spanProcessor: SpanProcessor { get { span.spanProcessor }}
  public var maxNumberOfAttributes: Int { get { span.maxNumberOfAttributes }}
  public var maxValueLengthPerSpanAttribute: Int  { get { span.maxValueLengthPerSpanAttribute }}
  public var maxNumberOfAttributesPerEvent: Int { get { span.maxNumberOfAttributesPerEvent }}
  public var kind: SpanKind { get { span.kind }}
  public var clock: Clock { get { span.clock }}
  public var resource: Resource { get { span.resource }}
  public var latency: TimeInterval { get { span.latency }}
  public var instrumentationScopeInfo: InstrumentationScopeInfo {
    get { span.instrumentationScopeInfo }
  }
  public var startTime: Date { get { span.startTime }}
  public var endTime: Date? { get { span.endTime }}
  public var status: Status
  public init?(span: any ReadableSpan) {
    guard let recordEventsReadableSpan = span as? RecordEventsReadableSpan else { return nil }
    self.span = recordEventsReadableSpan
    name = recordEventsReadableSpan.name
    attributes = AttributesDictionary(
      capacity: recordEventsReadableSpan.maxNumberOfAttributes
    )
    totalAttributeCount = recordEventsReadableSpan.totalAttributeCount
    totalRecordedEvents = recordEventsReadableSpan.totalRecordedEvents
    totalRecordedLinks = recordEventsReadableSpan.totalRecordedLinks
    attributes.updateValues(attributes: recordEventsReadableSpan.toSpanData().attributes)
    events = ArrayWithCapacity<SpanData.Event>(
      capacity: recordEventsReadableSpan.spanLimits.eventCountLimit)

    for event in recordEventsReadableSpan.events {
      events.append(event)
    }

    links = recordEventsReadableSpan.links
    status = recordEventsReadableSpan.status
  }

  public func recordException(
    _ exception: any OpenTelemetryApi.SpanException,
    attributes: [String : OpenTelemetryApi.AttributeValue]
  ) {
    recordException(exception, attributes: attributes, timestamp: clock.now)
  }

  public func setAttribute(
    key: String,
    value: OpenTelemetryApi.AttributeValue?
  ) {
    if value == nil {
      if attributes.removeValueForKey(key: key) != nil {
        totalAttributeCount -= 1
      }
      return
    }
    totalAttributeCount += 1
    if attributes[key] == nil, totalAttributeCount > maxNumberOfAttributes {
      return
    }
    /// Process only `string` type value
    if case let .string(value) = value {
      let formattedValue = value.count > maxValueLengthPerSpanAttribute ? String(value.prefix(maxValueLengthPerSpanAttribute)) : value
      attributes[key] = AttributeValue(formattedValue)
    } else {
      attributes[key] = value
    }
  }

  public func recordException(
    _ exception: any OpenTelemetryApi.SpanException,
    timestamp: Date
  ) {
    recordException(exception, attributes: [:], timestamp: timestamp)
  }

  public func recordException(_ exception: any SpanException, attributes: [String: AttributeValue], timestamp: Date) {
    var limitedAttributes = AttributesDictionary(capacity: maxNumberOfAttributesPerEvent)
    limitedAttributes.updateValues(attributes: attributes)
    limitedAttributes.updateValues(attributes: exception.eventAttributes)
    addEvent(
      event: SpanData
        .Event(
          name: SemanticAttributes.exception.rawValue,
          timestamp: timestamp,
          attributes: limitedAttributes.toDictonary()
        )
    )
  }


  public func toSpanData() -> SpanData {
    self.finish().toSpanData()
  }

  public func end() {
    end(time: clock.now)
  }

  public func end(time: Date) {
    span.end(time: time)
  }

  public var isRecording: Bool { get { span.isRecording }}

  public func addEvent(name: String) {
    addEvent(event: SpanData.Event(name: name, timestamp: clock.now))

  }

  public func addEvent(name: String, timestamp: Date) {
    addEvent(event: SpanData.Event(name: name, timestamp: timestamp))
  }

  public func addEvent(
    name: String,
    attributes: [String : OpenTelemetryApi.AttributeValue]
  ) {
    var limitedAttributes = AttributesDictionary(capacity: maxNumberOfAttributesPerEvent)
    limitedAttributes.updateValues(attributes: attributes)
    self.addEvent(
      event: SpanData.Event(
          name: name,
          timestamp: clock.now,
          attributes:limitedAttributes.toDictonary()
      )
    )
  }

  public func addEvent(
    name: String,
    attributes: [String : OpenTelemetryApi.AttributeValue],
    timestamp: Date
  ) {
    var limitedAttributes = AttributesDictionary(capacity: maxNumberOfAttributesPerEvent)
    limitedAttributes.updateValues(attributes: attributes)
    addEvent(
      event: SpanData
        .Event(
          name: name,
          timestamp: timestamp,
          attributes: limitedAttributes.toDictonary()
        )
    )
  }

  private func addEvent(event: SpanData.Event) {
    events.append(event)
    totalRecordedEvents += 1
  }

  public func recordException(_ exception: any OpenTelemetryApi.SpanException) {
    self.recordException(exception, attributes: [:], timestamp: clock.now)
  }

  public func finish() -> RecordEventsReadableSpan {
    var attributeDictionary = AttributesDictionary(capacity: maxNumberOfAttributesPerEvent)
    attributeDictionary.updateValues(attributes: attributes)
    let newSpan =  RecordEventsReadableSpan.startSpan(
      context: span.context,
      name: span.name,
      instrumentationScopeInfo: span.instrumentationScopeInfo,
      kind: span.kind,
      parentContext: span.parentContext,
      hasRemoteParent: span.hasRemoteParent,
      spanLimits: span.spanLimits,
      spanProcessor: NoopSpanProcessor(),
      clock: span.clock,
      resource: span.resource,
      attributes: attributeDictionary,
      links: span.links,
      totalRecordedLinks: span.totalRecordedLinks,
      startTime: span.startTime)

    events.forEach { event in
      newSpan.addEvent(name: event.name, attributes: event.attributes, timestamp: event.timestamp)
    }

    if let endTime = span.endTime {
      newSpan.end(time: endTime)
    } else {
      newSpan.end()
    }
    return newSpan
  }
}
