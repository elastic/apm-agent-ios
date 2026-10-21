// Copyright © 2026 Elasticsearch BV
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

import ElasticApmTestSupport
import Foundation
import NIO
import OpenTelemetryApi
import OpenTelemetrySdk
import URLSessionInstrumentation
import XCTest

@testable import ElasticApm

final class InstrumentationWrapperTests: XCTestCase {
  func testDefaultURLSessionConfigurationUsesStableHTTPConventions() {
    let configuration = makeWrapper(useLegacyAttributeNames: false)
      .makeURLSessionInstrumentationConfiguration()

    guard case .stable = configuration.semanticConvention else {
      return XCTFail("Default URLSession instrumentation must use stable HTTP conventions")
    }
  }

  func testLegacyURLSessionConfigurationUsesOldHTTPConventions() {
    let configuration = makeWrapper(useLegacyAttributeNames: true)
      .makeURLSessionInstrumentationConfiguration()

    guard case .old = configuration.semanticConvention else {
      return XCTFail("Legacy URLSession instrumentation must use old HTTP conventions")
    }
  }

  func testURLSessionStableErrorWithoutResponseRemovesStatusAndSetsErrorType() throws {
    let span = try receiveURLSessionError(
      status: 0,
      statusKey: SemanticConventions.Http.responseStatusCode.rawValue,
      useLegacyAttributeNames: false)

    XCTAssertNil(span.attributes[SemanticConventions.Http.responseStatusCode.rawValue])
    let errorType = try XCTUnwrap(
      span.attributes[SemanticConventions.Error.type.rawValue]?.description)
    XCTAssertEqual(errorType, String(describing: TestError.self))
    let exception = try XCTUnwrap(span.events.first)
    XCTAssertEqual(exception.name, SemanticConventions.Exception.exception.rawValue)
    XCTAssertEqual(
      exception.attributes[SemanticConventions.Exception.type.rawValue]?.description,
      errorType)
    XCTAssertEqual(span.events.count, 1)
  }

  func testURLSessionLegacyErrorWithoutResponseRemovesStatusAndSetsErrorType() throws {
    let span = try receiveURLSessionError(
      status: 0,
      statusKey: "http.status_code",
      useLegacyAttributeNames: true)

    XCTAssertNil(span.attributes["http.status_code"])
    XCTAssertEqual(
      span.attributes[SemanticConventions.Error.type.rawValue]?.description,
      String(describing: TestError.self))
  }

  func testURLSessionErrorWithResponseKeepsStatusWithoutSettingErrorType() throws {
    let span = try receiveURLSessionError(
      status: 503,
      statusKey: SemanticConventions.Http.responseStatusCode.rawValue,
      useLegacyAttributeNames: false)

    XCTAssertEqual(
      span.attributes[SemanticConventions.Http.responseStatusCode.rawValue]?.description,
      "503")
    XCTAssertNil(span.attributes[SemanticConventions.Error.type.rawValue])
    XCTAssertEqual(span.events.count, 1)
  }

  func testURLSessionConfigurationExcludesRegisteredHTTPSignalEndpoints() throws {
    let exportURL = URL(string: "https://export.example.com:4318/otlp")!
    let manager = makeManager(exportURL: exportURL)
    initializeWithInjectedExporters(manager, connectionType: .http)
    let shouldInstrument = try XCTUnwrap(
      InstrumentationWrapper(config: manager)
        .makeURLSessionInstrumentationConfiguration()
        .shouldInstrument)

    let registeredURLs = [
      URL(string: "\(exportURL)/v1/traces")!,
      URL(string: "\(exportURL)/v1/metrics")!,
      URL(string: "\(exportURL)/v1/logs")!
    ]
    XCTAssertEqual(manager.registeredEndpointCount, registeredURLs.count)
    for url in registeredURLs {
      XCTAssertEqual(
        shouldInstrument(URLRequest(url: url)),
        false,
        "Expected \(url) to be excluded")
    }

    XCTAssertEqual(
      shouldInstrument(
        URLRequest(url: URL(string: "\(exportURL)/v1/traces?retry=1")!)),
      false)
    XCTAssertNotEqual(
      shouldInstrument(URLRequest(url: URL(string: "\(exportURL)/v1/forecast")!)),
      false)
    XCTAssertNotEqual(
      shouldInstrument(
        URLRequest(url: URL(string: "https://export.example.com:4318/v1/traces")!)),
      false)
    XCTAssertNotEqual(
      shouldInstrument(
        URLRequest(url: URL(string: "https://app.example.com:4318/otlp/v1/traces")!)),
      false)
  }

  func testURLSessionConfigurationExcludesGrpcEndpoint() throws {
    let exportURL = URL(string: "https://export.example.com:4318/otlp")!
    let manager = makeManager(exportURL: exportURL)
    initializeWithInjectedExporters(manager, connectionType: .grpc)
    let shouldInstrument = try XCTUnwrap(
      InstrumentationWrapper(config: manager)
        .makeURLSessionInstrumentationConfiguration()
        .shouldInstrument)

    XCTAssertEqual(manager.registeredEndpointCount, 1)
    XCTAssertEqual(shouldInstrument(URLRequest(url: exportURL)), false)
  }

  func testURLSessionConfigurationNormalizesRegisteredTargets() throws {
    let exportURL = URL(string: "https://EXPORT.example.com/otlp")!
    let manager = makeManager(exportURL: exportURL)
    initializeWithInjectedExporters(manager, connectionType: .http)
    let shouldInstrument = try XCTUnwrap(
      InstrumentationWrapper(config: manager)
        .makeURLSessionInstrumentationConfiguration()
        .shouldInstrument)

    XCTAssertEqual(
      shouldInstrument(
        URLRequest(
          url: URL(string: "https://export.example.com:443/otlp/v1/traces/?retry=1#result")!
        )),
      false)
  }

  func testURLSessionConfigurationExcludesDerivedManagementURL() throws {
    let exportURL = URL(string: "https://export.example.com:4318/otlp")!
    let manager = makeManager(exportURL: exportURL, enableOpAMP: true)
    let shouldInstrument = try XCTUnwrap(
      InstrumentationWrapper(config: manager)
        .makeURLSessionInstrumentationConfiguration()
        .shouldInstrument)

    XCTAssertEqual(
      shouldInstrument(
        URLRequest(url: URL(string: "\(exportURL)/config/v1/agents/?retry=1")!)),
      false)
  }

  func testURLSessionConfigurationExcludesExplicitManagementURLOnly() throws {
    let exportURL = URL(string: "https://export.example.com:4318")!
    let managementURL = URL(string: "https://management.example.com:8443/custom/config/")!
    let manager = makeManager(
      exportURL: exportURL,
      managementURL: managementURL,
      enableOpAMP: true)
    let shouldInstrument = try XCTUnwrap(
      InstrumentationWrapper(config: manager)
        .makeURLSessionInstrumentationConfiguration()
        .shouldInstrument)

    XCTAssertEqual(
      shouldInstrument(URLRequest(url: managementURL)),
      false)
    XCTAssertNotEqual(
      shouldInstrument(
        URLRequest(url: URL(string: "\(exportURL)/config/v1/agents")!)),
      false)
  }

  func testURLSessionConfigurationExcludesFallbackManagementURL() throws {
    let manager = makeManager(enableOpAMP: true)
    let shouldInstrument = try XCTUnwrap(
      InstrumentationWrapper(config: manager)
        .makeURLSessionInstrumentationConfiguration()
        .shouldInstrument)

    XCTAssertEqual(
      shouldInstrument(
        URLRequest(url: URL(string: "http://localhost:4320/v1/opamp")!)),
      false)
  }

  func testURLSessionConfigurationDoesNotExcludeWhenExportURLCannotBeResolved() throws {
    let manager = makeManager()
    initializeWithInjectedExporters(manager, connectionType: .http)
    let shouldInstrument = try XCTUnwrap(
      InstrumentationWrapper(config: manager)
        .makeURLSessionInstrumentationConfiguration()
        .shouldInstrument)

    XCTAssertEqual(manager.registeredEndpointCount, 0)
    XCTAssertNotEqual(
      shouldInstrument(
        URLRequest(url: URL(string: "https://export.example.com:4318/v1/traces")!)),
      false)
  }

  private func makeWrapper(
    useLegacyAttributeNames: Bool = false
  ) -> InstrumentationWrapper {
    InstrumentationWrapper(
      config: makeManager(useLegacyAttributeNames: useLegacyAttributeNames))
  }

  private func receiveURLSessionError(
    status: Int,
    statusKey: String,
    useLegacyAttributeNames: Bool
  ) throws -> SpanData {
    let configuration = makeWrapper(useLegacyAttributeNames: useLegacyAttributeNames)
      .makeURLSessionInstrumentationConfiguration()
    let receivedError = try XCTUnwrap(configuration.receivedError)
    let tracer = TracerProviderBuilder()
      .build()
      .get(instrumentationName: "InstrumentationWrapperTests")
    let span = tracer.spanBuilder(spanName: "test-url-session-error")
      .setAttribute(key: statusKey, value: .int(status))
      .startSpan()

    receivedError(TestError.failure, nil, status, span)

    return try XCTUnwrap(span as? any ReadableSpan).toSpanData()
  }

  private func makeManager(
    useLegacyAttributeNames: Bool = false,
    exportURL: URL? = nil,
    managementURL: URL? = nil,
    enableOpAMP: Bool = false
  ) -> AgentConfigManager {
    let builder = AgentConfigBuilder()
      .useLegacyAttributeNames(useLegacyAttributeNames)
    if let exportURL {
      _ = builder.withExportUrl(exportURL)
    }
    if let managementURL {
      _ = builder.withManagementUrl(managementURL)
    }
    if enableOpAMP {
      _ = builder.useOpAMP()
    }
    let instrumentationConfiguration = InstrumentationConfigBuilder()
      .withLifecycleEvents(false)
      .withViewControllerInstrumentation(false)
      .withSystemMetrics(false)
      .build()
    let manager = AgentConfigManager(
      resource: Resource(),
      config: builder.build(),
      instrumentationConfig: instrumentationConfiguration
    )
    return manager
  }

  private func initializeWithInjectedExporters(
    _ manager: AgentConfigManager,
    connectionType: AgentConnectionType
  ) {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let initializer = OpenTelemetryInitializer(
      group: group,
      sessionSampler: SessionSampler { 1.0 },
      exporters: OpenTelemetryInitializer.Exporters(
        metric: WaitingMetricExporter(numberToWaitFor: 1),
        trace: WaitingSpanExporter(numberToWaitFor: 1),
        log: WaitingLogRecordExporter(numberToWaitFor: 1)))

    switch connectionType {
    case .grpc:
      _ = initializer.initialize(manager)
    case .http:
      _ = initializer.initializeWithHttp(manager)
    }

    if let tracerProvider = OpenTelemetry.instance.tracerProvider as? TracerProviderSdk {
      tracerProvider.shutdown()
    }
    if let meterProvider = OpenTelemetry.instance.meterProvider as? MeterProviderSdk {
      XCTAssertEqual(meterProvider.shutdown(), .success)
    }
    XCTAssertNoThrow(try group.syncShutdownGracefully())
  }
}

private enum TestError: Error {
  case failure
}
