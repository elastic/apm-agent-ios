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

class SessionSpanProcessorTest: XCTestCase {
  let spanName1 = "MySpanName/1"
  var tracer: Tracer!
  let tracerSdkFactory = TracerProviderSdk()
  let maxScheduleDelay = 0.5

  override func setUp() {
    tracer = tracerSdkFactory.get(instrumentationName: "BatchSpansProcessorTest")
  }

  override func tearDown() {
    tracerSdkFactory.shutdown()
  }

  @discardableResult private func createSampledHttpSpan(spanName: String) -> ReadableSpan {
    let span = tracer.spanBuilder(spanName: spanName).setNoParent()
      .setAttribute(key: SemanticAttributes.httpUrl.rawValue, value: "http://localhost").startSpan()
    span.end()
    return span as! ReadableSpan
  }

  @discardableResult private func createSampledEndedSpan(spanName: String) -> ReadableSpan {
    let span = tracer.spanBuilder(spanName: spanName).startSpan()
    span.end()
    return span as! ReadableSpan
  }

  func testSessionId() {
    let waitingSpanExporter = WaitingSpanExporter(numberToWaitFor: 1)
    let config = AgentConfiguration()
    tracerSdkFactory
      .addSpanProcessor(
        ElasticSpanProcessor(
          spanExporter: waitingSpanExporter,
          agentConfiguration: config, scheduleDelay: maxScheduleDelay
        )
      )
    _ = createSampledEndedSpan(spanName: spanName1)
    let exported = waitingSpanExporter.waitForExport()
    XCTAssertEqual(exported?.count, 1)
    XCTAssertNotNil(exported?[0].attributes["session.id"])
  }

  func testSpanFiltering() {
    let waitingSpanExporter = WaitingSpanExporter(numberToWaitFor: 1)
    var config = AgentConfiguration()
    config.spanFilters = [SignalFilter<any ReadableSpan> { span in
      span.name != self.spanName1
    }]
    tracerSdkFactory.addSpanProcessor(ElasticSpanProcessor(
      spanExporter: waitingSpanExporter,
      agentConfiguration: config,
      scheduleDelay: maxScheduleDelay))
    _ = createSampledEndedSpan(spanName: spanName1)
    _ = createSampledEndedSpan(spanName: "Some Span")
    let exported = waitingSpanExporter.waitForExport()

    XCTAssertEqual(exported?.count, 1)
  }

  func testHttpSpansAreIntercepted() {
    let waitingSpanExporter = WaitingSpanExporter(numberToWaitFor: 2)
    let config = AgentConfigBuilder()
      .addSpanAttributeInterceptor(ClosureInterceptor { attributes in
        var attributes = attributes
        attributes["test"] = .bool(true)
        return attributes
      })
      .build()
    tracerSdkFactory
      .addSpanProcessor(
        ElasticSpanProcessor(
          spanExporter: waitingSpanExporter,
          agentConfiguration: config, scheduleDelay: maxScheduleDelay
        )
      )
    _ = createSampledHttpSpan(spanName: spanName1)
    let exported = waitingSpanExporter.waitForExport()
    XCTAssertEqual(exported?.count, 2)
    XCTAssertNotNil(exported?[0].attributes["test"])
    XCTAssertNotNil(exported?[1].attributes["test"])
  }

  func testOrphanHttpSpans() {
    let waitingSpanExporter = WaitingSpanExporter(numberToWaitFor: 2)
    let config = AgentConfiguration()
    tracerSdkFactory
      .addSpanProcessor(
        ElasticSpanProcessor(
          spanExporter: waitingSpanExporter,
          agentConfiguration: config, scheduleDelay: maxScheduleDelay
        )
      )
    _ = createSampledHttpSpan(spanName: spanName1)
    let exported = waitingSpanExporter.waitForExport()
    XCTAssertEqual(exported?.count, 2)
    XCTAssertNotNil(exported?[0].attributes["session.id"])
    XCTAssertNotNil(exported?[1].attributes["session.id"])
    XCTAssertEqual(exported?[0].traceId, exported?[1].traceId)
  }
  func testHttpSpansWithParent() {
    let waitingSpanExporter = WaitingSpanExporter(numberToWaitFor: 1)
    let config = AgentConfiguration()
    tracerSdkFactory
      .addSpanProcessor(
        ElasticSpanProcessor(
          spanExporter: waitingSpanExporter,
          agentConfiguration: config, scheduleDelay: maxScheduleDelay
        )
      )
    _ = createSampledHttpSpan(spanName: spanName1)
    let exported = waitingSpanExporter.waitForExport()
    XCTAssertEqual(exported?.count, 2)
    XCTAssertNotNil(exported?[0].attributes["session.id"])
    XCTAssertNotNil(exported?[1].attributes["session.id"])
    XCTAssertEqual(exported?[0].traceId, exported?[1].traceId)
  }

  func testSpanInterceptors() {
    let waitingSpanExporter = WaitingSpanExporter(numberToWaitFor: 1)
    var config = AgentConfiguration()
    config.spanAttributeInterceptor = ClosureInterceptor<[String:AttributeValue]> { attribute in
      var newAttributes = attribute
      newAttributes["foo"] = .string("bar")
      return newAttributes
    }
    tracerSdkFactory
      .addSpanProcessor(
        ElasticSpanProcessor(
          spanExporter: waitingSpanExporter,
          agentConfiguration: config,
          scheduleDelay: maxScheduleDelay
        )
      )
    _ = createSampledHttpSpan(spanName: spanName1)
    let exported = waitingSpanExporter.waitForExport()

    XCTAssertTrue(exported?[0].attributes["foo"]?.description == "bar")
  }
}

class WaitingSpanExporter: SpanExporter {
  var spanDataList = [SpanData]()
  let cond = NSCondition()
  let numberToWaitFor: Int
  var shutdownCalled = false

  init(numberToWaitFor: Int) {
    self.numberToWaitFor = numberToWaitFor
  }

  func waitForExport() -> [SpanData]? {
    var ret: [SpanData]
    cond.lock()
    defer { cond.unlock() }

    while spanDataList.count < numberToWaitFor {
      cond.wait()
    }
    ret = spanDataList
    spanDataList.removeAll()

    return ret
  }

  func export(spans: [SpanData], explicitTimeout: TimeInterval? = nil) -> SpanExporterResultCode {
    cond.lock()
    spanDataList.append(contentsOf: spans)
    cond.unlock()
    cond.broadcast()
    return .success
  }

  func flush(explicitTimeout: TimeInterval? = nil) -> SpanExporterResultCode {
    return .success
  }

  func shutdown(explicitTimeout: TimeInterval? = nil) {
    shutdownCalled = true
  }
}
