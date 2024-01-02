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
@testable import iOSAgent
import XCTest

class ElasticLogRecordProcessorTest: XCTestCase {

    func testSessionId() {
        let waitingExporter = WaitingLogRecordExporter(numberToWaitFor: 1)

        let  factory = LoggerProviderSdk(logRecordProcessors: [ElasticLogRecordProcessor(logRecordExporter: waitingExporter, scheduleDelay: 0.5)])
        let logger = factory.loggerBuilder(instrumentationScopeName: "SessionLogRecordProcessorTests").setEventDomain("device").build()
        let observedDate = Date()

        let eventBuilder = logger.eventBuilder(name: "myEvent")
        eventBuilder.setBody(AttributeValue.string("hello, world"))
        .setSeverity(.fatal)
        .setObservedTimestamp(observedDate)
        .emit()
        let exported = waitingExporter.waitForExport()
        XCTAssertEqual(exported?.count, 1)
        XCTAssertNotNil(exported?[0].attributes["session.id"])
        XCTAssertEqual(exported?[0].attributes["session.id"]?.description, SessionManager.instance.session())
        XCTAssertEqual(exported?[0].attributes["event.domain"]?.description, "device")
        XCTAssertEqual(exported?[0].attributes["event.name"]?.description, "myEvent")
        XCTAssertEqual(exported?[0].body, AttributeValue.string("hello, world"))
        XCTAssertEqual(exported?[0].severity, .fatal)
        XCTAssertEqual(exported?[0].observedTimestamp, observedDate)

    }
}

class WaitingLogRecordExporter: LogRecordExporter {
    var logRecordList = [ReadableLogRecord]()
    let cond = NSCondition()
    let numberToWaitFor: Int
    var shutdownCalled = false

    init(numberToWaitFor: Int) {
        self.numberToWaitFor = numberToWaitFor
    }

    func export(logRecords: [OpenTelemetrySdk.ReadableLogRecord], explicitTimeout: TimeInterval? = nil) -> OpenTelemetrySdk.ExportResult {
        cond.lock()
        logRecordList.append(contentsOf: logRecords)
        cond.unlock()
        cond.broadcast()
        return .success
    }

    func waitForExport() -> [ReadableLogRecord]? {
        var ret: [ReadableLogRecord]
        cond.lock()
        defer { cond.unlock() }

        while logRecordList.count < numberToWaitFor {
            cond.wait()
        }
        ret = logRecordList
        logRecordList.removeAll()

        return ret
    }

    func forceFlush(explicitTimeout: TimeInterval? = nil) -> ExportResult {
        return .success
    }

    func shutdown(explicitTimeout: TimeInterval? = nil) {
        shutdownCalled = true
    }
}
