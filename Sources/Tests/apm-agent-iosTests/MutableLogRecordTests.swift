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

import OpenTelemetryApi
import OpenTelemetrySdk
@testable import ElasticApm
import XCTest

final class MutableLogRecordTests: XCTestCase {
  func testFinishPreservesCoreFieldsAndAppliesAttributeChanges() throws {
    let waitingExporter = WaitingLogRecordExporter(numberToWaitFor: 1)
    let factory = LoggerProviderSdk(
      logRecordProcessors: [
        ElasticLogRecordProcessor(
          logRecordExporter: waitingExporter,
          configuration: AgentConfiguration(),
          scheduleDelay: 0.5
        )
      ]
    )
    let logger = factory.loggerBuilder(instrumentationScopeName: "MutableLogRecordTests")
      .build()
    let observedDate = Date(timeIntervalSince1970: 1_700_000_000)

    logger.logRecordBuilder()
      .setEventName("probe")
      .setBody(AttributeValue.string("body"))
      .setSeverity(.info)
      .setObservedTimestamp(observedDate)
      .emit()

    let exported = waitingExporter.waitForExport()
    XCTAssertEqual(exported?.count, 1)
    let original = try XCTUnwrap(exported?[0])

    var mutable = MutableLogRecord(from: original)
    XCTAssertEqual(mutable.resource, original.resource)
    XCTAssertEqual(mutable.instrumentationScopeInfo, original.instrumentationScopeInfo)
    XCTAssertEqual(mutable.timestamp, original.timestamp)
    XCTAssertEqual(mutable.observedTimestamp, original.observedTimestamp)
    XCTAssertEqual(mutable.spanContext, original.spanContext)
    XCTAssertEqual(mutable.severity, original.severity)
    XCTAssertEqual(mutable.body, original.body)

    mutable.attributes["custom.key"] = .string("added")

    let finished = mutable.finish()
    XCTAssertEqual(finished.attributes["custom.key"], .string("added"))
    XCTAssertEqual(finished.body, original.body)
    XCTAssertEqual(finished.severity, original.severity)
    XCTAssertEqual(finished.observedTimestamp, original.observedTimestamp)
    XCTAssertEqual(finished.resource, original.resource)
  }
}
