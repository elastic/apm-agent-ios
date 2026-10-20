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
import ElasticApmTestSupport
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
      .setSpanKind(spanKind: .client)
      .setAttribute(key: SemanticAttributes.httpUrl.rawValue, value: "http://localhost")
      .setAttribute(key: SemanticConventions.Url.full.rawValue, value: "http://localhost")
      .startSpan()
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

  func testHttpSpansAreIntercepted() throws {
    let waitingSpanExporter = WaitingSpanExporter(numberToWaitFor: 1)
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
    let exported = try XCTUnwrap(waitingSpanExporter.waitForExport())
    XCTAssertEqual(exported.count, 1)
    XCTAssertEqual(exported.first?.attributes["test"], .bool(true))
  }

  func testOrphanHttpSpans() throws {
    let waitingSpanExporter = WaitingSpanExporter(numberToWaitFor: 1)
    let config = AgentConfiguration()
    tracerSdkFactory
      .addSpanProcessor(
        ElasticSpanProcessor(
          spanExporter: waitingSpanExporter,
          agentConfiguration: config, scheduleDelay: maxScheduleDelay
        )
      )
    let created = createSampledHttpSpan(spanName: spanName1)
    let exported = try XCTUnwrap(waitingSpanExporter.waitForExport())
    XCTAssertEqual(exported.count, 1)
    let httpSpan = try XCTUnwrap(exported.first)
    XCTAssertNil(httpSpan.parentSpanId)
    XCTAssertEqual(httpSpan.spanId, created.context.spanId)
    XCTAssertEqual(httpSpan.traceId, created.context.traceId)
    XCTAssertEqual(httpSpan.name, created.name)
    XCTAssertEqual(httpSpan.kind, created.kind)
    XCTAssertEqual(httpSpan.attributes, created.getAttributes())
    XCTAssertNotNil(httpSpan.attributes["session.id"])
    XCTAssertEqual(httpSpan.attributes["type"], .string("mobile"))
    XCTAssertNil(waitingSpanExporter.waitForExport(timeout: maxScheduleDelay * 2))
  }

  func testHttpSpansWithParent() throws {
    let waitingSpanExporter = WaitingSpanExporter(numberToWaitFor: 2)
    let config = AgentConfiguration()
    tracerSdkFactory
      .addSpanProcessor(
        ElasticSpanProcessor(
          spanExporter: waitingSpanExporter,
          agentConfiguration: config, scheduleDelay: maxScheduleDelay
        )
      )
    let parent = tracer.spanBuilder(spanName: "Parent").setNoParent().startSpan()
    let child = tracer.spanBuilder(spanName: spanName1)
      .setParent(parent)
      .setSpanKind(spanKind: .client)
      .setAttribute(key: SemanticAttributes.httpUrl.rawValue, value: "http://localhost")
      .setAttribute(key: SemanticConventions.Url.full.rawValue, value: "http://localhost")
      .startSpan()
    child.end()
    parent.end()

    let exported = try XCTUnwrap(waitingSpanExporter.waitForExport())
    XCTAssertEqual(exported.count, 2)
    let parentSpan = try XCTUnwrap(exported.first { $0.spanId == parent.context.spanId })
    let httpSpan = try XCTUnwrap(exported.first { $0.spanId == child.context.spanId })
    XCTAssertNil(parentSpan.parentSpanId)
    XCTAssertEqual(httpSpan.parentSpanId, parentSpan.spanId)
    XCTAssertEqual(httpSpan.traceId, parentSpan.traceId)
    XCTAssertEqual(httpSpan.name, spanName1)
    XCTAssertEqual(httpSpan.kind, .client)
  }

  func testSpanInterceptors() {
    let waitingSpanExporter = WaitingSpanExporter(numberToWaitFor: 1)
    var config = AgentConfiguration()
    config.spanAttributeInterceptor = AnyInterceptor(ClosureInterceptor<[String: AttributeValue]> { attribute in
      var newAttributes = attribute
      newAttributes["foo"] = .string("bar")
      return newAttributes
    })
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

  // Keep the body in sync with the addSpanAttributeInterceptor(_:) example in
  // docs/reference/edot-ios/configuration.md.
  func testDocumentedSpanAttributeInterceptorCall() {
    let waitingSpanExporter = WaitingSpanExporter(numberToWaitFor: 1)

    let interceptor = ClosureInterceptor<[String: AttributeValue]> { attributes in
      var updatedAttributes = attributes
      updatedAttributes["myapp.release_channel"] = .string("beta")
      return updatedAttributes
    }

    let configuration = AgentConfigBuilder()
      .withExportUrl(URL(string: "https://your-otlp-endpoint")!)
      .addSpanAttributeInterceptor(interceptor)
      .build()

    tracerSdkFactory
      .addSpanProcessor(
        ElasticSpanProcessor(
          spanExporter: waitingSpanExporter,
          agentConfiguration: configuration,
          scheduleDelay: maxScheduleDelay
        )
      )
    _ = createSampledEndedSpan(spanName: spanName1)
    let exported = waitingSpanExporter.waitForExport()

    XCTAssertEqual(exported?[0].attributes["myapp.release_channel"]?.description, "beta")
  }
}
