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

public struct MutableLogRecord {
  private var logRecord: ReadableLogRecord
  public var attributes: [String: AttributeValue]

  public var resource: Resource {
    get {
      logRecord.resource
    }
  }

  public var instrumentationScopeInfo: InstrumentationScopeInfo {
    get {
      logRecord.instrumentationScopeInfo
    }
  }

  public var timestamp: Date {
    get {
      logRecord.timestamp
    }
  }

  public var observedTimestamp: Date? {
    get {
      logRecord.observedTimestamp
    }
  }

  public var spanContext: SpanContext? {
    get {
      logRecord.spanContext
    }
  }

  public var severity: Severity? {
    get {
      logRecord.severity
    }
  }

  public var body: AttributeValue? {
    get {
      logRecord.body
    }
  }

  public init(from logRecord: ReadableLogRecord) {
    self.logRecord = logRecord
    self.attributes = logRecord.attributes
  }


  public func finish() -> ReadableLogRecord {
    return ReadableLogRecord(resource: logRecord.resource,
                             instrumentationScopeInfo: logRecord.instrumentationScopeInfo,
                             timestamp: logRecord.timestamp,
                             observedTimestamp: logRecord.observedTimestamp,
                             spanContext: logRecord.spanContext,
                             severity: logRecord.severity,
                             body: logRecord.body,
                             attributes: attributes)
  }
}
