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
@testable import ElasticApm
import XCTest

class ApplicationLifecycleInstrumentationTest: XCTestCase {
    func testLifecycleActive() {
        let waitingExporter = WaitingLogRecordExporter(numberToWaitFor: 1)

        let  factory = LoggerProviderSdk(logRecordProcessors: [ElasticLogRecordProcessor(logRecordExporter: waitingExporter, scheduleDelay: 0.5)])

        OpenTelemetry.registerLoggerProvider(loggerProvider: factory)

        let appLifecycleInstrumentation = ApplicationLifecycleInstrumentation()
        appLifecycleInstrumentation.active(Notification(name: Notification.Name("test")))

        let exported = waitingExporter.waitForExport()

        XCTAssertEqual(exported?.count, 1)
        XCTAssertNotNil(exported?[0].attributes["event.name"])
        XCTAssertNotNil(exported?[0].attributes["event.domain"])
        XCTAssertNotNil(exported?[0].attributes["lifecycle.state"])
        XCTAssertEqual(exported?[0].attributes["event.name"]?.description, "lifecycle")
        XCTAssertEqual(exported?[0].attributes["event.domain"]?.description, "device")
        XCTAssertEqual(exported?[0].attributes["lifecycle.state"]?.description, "active")
    }

    func testLifecycleInactive() {
        let waitingExporter = WaitingLogRecordExporter(numberToWaitFor: 1)

        let  factory = LoggerProviderSdk(logRecordProcessors: [ElasticLogRecordProcessor(logRecordExporter: waitingExporter, scheduleDelay: 0.5)])

        OpenTelemetry.registerLoggerProvider(loggerProvider: factory)

        let appLifecycleInstrumentation = ApplicationLifecycleInstrumentation()
        appLifecycleInstrumentation.inactive(Notification(name: Notification.Name("test")))

        let exported = waitingExporter.waitForExport()

        XCTAssertEqual(exported?.count, 1)
        XCTAssertNotNil(exported?[0].attributes["event.name"])
        XCTAssertNotNil(exported?[0].attributes["event.domain"])
        XCTAssertNotNil(exported?[0].attributes["lifecycle.state"])
        XCTAssertEqual(exported?[0].attributes["event.name"]?.description, "lifecycle")
        XCTAssertEqual(exported?[0].attributes["event.domain"]?.description, "device")
        XCTAssertEqual(exported?[0].attributes["lifecycle.state"]?.description, "inactive")
    }

    func testLifecycleBackground() {
        let waitingExporter = WaitingLogRecordExporter(numberToWaitFor: 1)

        let  factory = LoggerProviderSdk(logRecordProcessors: [ElasticLogRecordProcessor(logRecordExporter: waitingExporter, scheduleDelay: 0.5)])

        OpenTelemetry.registerLoggerProvider(loggerProvider: factory)

        let appLifecycleInstrumentation = ApplicationLifecycleInstrumentation()
        appLifecycleInstrumentation.background(Notification(name: Notification.Name("test")))

        let exported = waitingExporter.waitForExport()

        XCTAssertEqual(exported?.count, 1)
        XCTAssertNotNil(exported?[0].attributes["event.name"])
        XCTAssertNotNil(exported?[0].attributes["event.domain"])
        XCTAssertNotNil(exported?[0].attributes["lifecycle.state"])
        XCTAssertEqual(exported?[0].attributes["event.name"]?.description, "lifecycle")
        XCTAssertEqual(exported?[0].attributes["event.domain"]?.description, "device")
        XCTAssertEqual(exported?[0].attributes["lifecycle.state"]?.description, "background")
    }
    func testLifecycleForeground() {
        let waitingExporter = WaitingLogRecordExporter(numberToWaitFor: 1)

        let  factory = LoggerProviderSdk(logRecordProcessors: [ElasticLogRecordProcessor(logRecordExporter: waitingExporter, scheduleDelay: 0.5)])

        OpenTelemetry.registerLoggerProvider(loggerProvider: factory)

        let appLifecycleInstrumentation = ApplicationLifecycleInstrumentation()
        appLifecycleInstrumentation.foreground(Notification(name: Notification.Name("test")))

        let exported = waitingExporter.waitForExport()

        XCTAssertEqual(exported?.count, 1)
        XCTAssertNotNil(exported?[0].attributes["event.name"])
        XCTAssertNotNil(exported?[0].attributes["event.domain"])
        XCTAssertNotNil(exported?[0].attributes["lifecycle.state"])
        XCTAssertEqual(exported?[0].attributes["event.name"]?.description, "lifecycle")
        XCTAssertEqual(exported?[0].attributes["event.domain"]?.description, "device")
        XCTAssertEqual(exported?[0].attributes["lifecycle.state"]?.description, "foreground")
    }

    func testLifecycleTerminate() {
        let waitingExporter = WaitingLogRecordExporter(numberToWaitFor: 1)

        let  factory = LoggerProviderSdk(logRecordProcessors: [ElasticLogRecordProcessor(logRecordExporter: waitingExporter, scheduleDelay: 0.5)])

        OpenTelemetry.registerLoggerProvider(loggerProvider: factory)

        let appLifecycleInstrumentation = ApplicationLifecycleInstrumentation()
        appLifecycleInstrumentation.terminate(Notification(name: Notification.Name("test")))

        let exported = waitingExporter.waitForExport()

        XCTAssertEqual(exported?.count, 1)
        XCTAssertNotNil(exported?[0].attributes["event.name"])
        XCTAssertNotNil(exported?[0].attributes["event.domain"])
        XCTAssertNotNil(exported?[0].attributes["lifecycle.state"])
        XCTAssertEqual(exported?[0].attributes["event.name"]?.description, "lifecycle")
        XCTAssertEqual(exported?[0].attributes["event.domain"]?.description, "device")
        XCTAssertEqual(exported?[0].attributes["lifecycle.state"]?.description, "terminate")
    }
}
