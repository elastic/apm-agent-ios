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

#if canImport(UIKit) && !os(watchOS) // UIApplication lifecycle events are unavailable on macOS and watchOS.
  import ElasticApmTestSupport
  import Foundation
  import OpenTelemetryApi
  import OpenTelemetrySdk
  @testable import ElasticApm
  import XCTest

  final class ApplicationLifecycleInstrumentationTest: XCTestCase {
    func testDefaultLifecycleEventsUseSemanticConventionNames() throws {
      try assertLifecycleEvents(useLegacyAttributeNames: false)
    }

    func testLegacyLifecycleEventsRestorePreviousNames() throws {
      try assertLifecycleEvents(useLegacyAttributeNames: true)
    }

    private func assertLifecycleEvents(useLegacyAttributeNames: Bool) throws {
      let cases: [
        (
          state: SemanticConventions.Ios.AppStateValues,
          emit: (ApplicationLifecycleInstrumentation) -> Void
        )
      ] = [
        (.active, { $0.active(Notification(name: Notification.Name("test"))) }),
        (.inactive, { $0.inactive(Notification(name: Notification.Name("test"))) }),
        (.background, { $0.background(Notification(name: Notification.Name("test"))) }),
        (.foreground, { $0.foreground(Notification(name: Notification.Name("test"))) }),
        (.terminate, { $0.terminate(Notification(name: Notification.Name("test"))) })
      ]

      let centralConfig = CentralConfig()
      let previousCentralConfig = centralConfig.config
      centralConfig.config = nil
      defer {
        centralConfig.config = previousCentralConfig
      }

      for lifecycleCase in cases {
        let exported = try exportLifecycleEvent(
          useLegacyAttributeNames: useLegacyAttributeNames,
          emit: lifecycleCase.emit
        )
        let expectedEventName =
          useLegacyAttributeNames ? "lifecycle" : "device.app.lifecycle"
        let expectedAttributeName =
          useLegacyAttributeNames ? "lifecycle.state" : "ios.app.state"
        let rejectedEventName =
          useLegacyAttributeNames ? "device.app.lifecycle" : "lifecycle"
        let rejectedAttributeName =
          useLegacyAttributeNames ? "ios.app.state" : "lifecycle.state"

        XCTAssertEqual(exported.eventName, expectedEventName)
        XCTAssertNotEqual(exported.eventName, rejectedEventName)
        XCTAssertEqual(
          exported.attributes[expectedAttributeName],
          .string(lifecycleCase.state.description)
        )
        XCTAssertNil(exported.attributes[rejectedAttributeName])
      }
    }

    private func exportLifecycleEvent(
      useLegacyAttributeNames: Bool,
      emit: (ApplicationLifecycleInstrumentation) -> Void
    ) throws -> ReadableLogRecord {
      let exporter = WaitingLogRecordExporter(numberToWaitFor: 1)
      let provider = LoggerProviderSdk(
        logRecordProcessors: [
          ElasticLogRecordProcessor(
            logRecordExporter: exporter,
            configuration: AgentConfigBuilder()
              .useLegacyAttributeNames(useLegacyAttributeNames)
              .build(),
            scheduleDelay: 0.01
          )
        ]
      )
      OpenTelemetry.registerLoggerProvider(loggerProvider: provider)

      let instrumentation = ApplicationLifecycleInstrumentation(
        useLegacyAttributeNames: useLegacyAttributeNames)
      emit(instrumentation)

      return try XCTUnwrap(exporter.waitForExport()?.first)
    }
  }
#else
  import XCTest

  final class ApplicationLifecycleInstrumentationTest: XCTestCase {
    func testUnsupportedPlatformReportsSkip() throws {
      #if os(macOS)
        throw XCTSkip("Application lifecycle instrumentation is unavailable on macOS without UIKit.")
      #else
        throw XCTSkip("Application lifecycle instrumentation is unavailable on watchOS.")
      #endif
    }
  }
#endif
