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

// EDOT currently supports iOS only; macOS retains the SwiftPM development loop.
#if os(iOS) || os(macOS)

  import ElasticApmTestSupport
  import Foundation
  import NIO
  import OpenTelemetryApi
  import OpenTelemetrySdk
  import XCTest

  @testable import ElasticApm

  class OTLPHTTPWireTestCase: XCTestCase {
    static let requestTimeout: TimeInterval = 25
    static let zeroRequestWindow: TimeInterval = 3

    let fileManager = FileManager.default
    var cachesDirectory: URL {
      get throws {
        try fileManager.url(
          for: .cachesDirectory,
          in: .userDomainMask,
          appropriateFor: nil,
          create: true
        ).appendingPathComponent("elastic", isDirectory: true)
      }
    }

    override func setUpWithError() throws {
      try super.setUpWithError()
      XCTAssertNil(
        ProcessInfo.processInfo.environment["OTEL_EXPORTER_OTLP_HEADERS"],
        "Wire tests require OTEL_EXPORTER_OTLP_HEADERS to be unset so the configured test authorization is used")
      try removePersistence()
    }

    override func tearDownWithError() throws {
      try removePersistence()
      try super.tearDownWithError()
    }

    func removePersistence() throws {
      let directory = try cachesDirectory
      if fileManager.fileExists(atPath: directory.path) {
        try fileManager.removeItem(at: directory)
      }
    }

    func assertNoPersistence(
      file: StaticString = #filePath,
      line: UInt = #line
    ) throws {
      let directory = try cachesDirectory
      XCTAssertFalse(
        fileManager.fileExists(atPath: directory.path),
        "Agent startup created persistence directories: \(directoryDiagnostics(at: directory))",
        file: file,
        line: line)
    }

    func uniqueCredential(prefix: String = "wire") -> String {
      "\(prefix)-\(UUID().uuidString)"
    }

    func matchingRequest(
      on server: LoopbackHTTPTestServer,
      authorization: String,
      timeout: TimeInterval = requestTimeout
    ) -> LoopbackHTTPTestServer.Request? {
      server.waitForRequest(timeout: timeout) {
        $0.header(named: "Authorization") == authorization
      }
    }
  }

  final class OTLPHTTPWireSignalTests: OTLPHTTPWireTestCase {
    func testSpanExportsByPOSTToTracesPath() throws {
      try withWirePipeline { harness in
        harness.emitSpan()

        let request = try XCTUnwrap(
          harness.waitForRequest(),
          harness.diagnostics)
        XCTAssertEqual(request.method, "POST", harness.diagnostics)
        XCTAssertEqual(request.path, "/v1/traces", harness.diagnostics)
      }
    }

    func testLogExportsByPOSTToLogsPath() throws {
      try withWirePipeline { harness in
        harness.emitLog()

        let request = try XCTUnwrap(
          harness.waitForRequest(),
          harness.diagnostics)
        XCTAssertEqual(request.method, "POST", harness.diagnostics)
        XCTAssertEqual(request.path, "/v1/logs", harness.diagnostics)
      }
    }

    func testMetricExportsByPOSTToMetricsPath() throws {
      try withWirePipeline { harness in
        try harness.emitMetric()

        let request = try XCTUnwrap(
          harness.waitForRequest(),
          harness.diagnostics)
        XCTAssertEqual(request.method, "POST", harness.diagnostics)
        XCTAssertEqual(request.path, "/v1/metrics", harness.diagnostics)
      }
    }
  }

  final class OTLPHTTPWireAuthenticationTests: OTLPHTTPWireTestCase {
    func testSecretTokenExportsExactAuthorizationHeader() throws {
      let token = uniqueCredential(prefix: "secret")
      try withWirePipeline(authentication: .secretToken(token)) { harness in
        harness.emitSpan()

        let request = try XCTUnwrap(harness.waitForRequest(), harness.diagnostics)
        XCTAssertEqual(request.header(named: "Authorization"), "Bearer \(token)")
      }
    }

    func testAPIKeyExportsExactAuthorizationHeader() throws {
      let key = uniqueCredential(prefix: "api-key")
      try withWirePipeline(authentication: .apiKey(key)) { harness in
        harness.emitSpan()

        let request = try XCTUnwrap(harness.waitForRequest(), harness.diagnostics)
        XCTAssertEqual(request.header(named: "Authorization"), "ApiKey \(key)")
      }
    }
  }

  final class OTLPHTTPWireEndpointTests: OTLPHTTPWireTestCase {
    func testEndpointChangeRedirectsSubsequentRequests() throws {
      let serverA = LoopbackHTTPTestServer()
      let serverB = LoopbackHTTPTestServer()
      try serverA.start()
      try serverB.start()
      defer {
        serverA.stop()
        serverB.stop()
      }

      let firstKey = uniqueCredential(prefix: "endpoint-a")
      let first = try WireTelemetryHarness(server: serverA, authentication: .apiKey(firstKey))
      first.emitSpan()
      XCTAssertNotNil(first.waitForRequest(), first.diagnostics)
      first.shutDown()

      let secondKey = uniqueCredential(prefix: "endpoint-b")
      let secondAuthorization = "ApiKey \(secondKey)"
      let second = try WireTelemetryHarness(server: serverB, authentication: .apiKey(secondKey))
      defer { second.shutDown() }
      second.emitSpan()

      XCTAssertNotNil(second.waitForRequest(), second.diagnostics)
      XCTAssertNil(
        matchingRequest(
          on: serverA,
          authorization: secondAuthorization,
          timeout: Self.zeroRequestWindow),
        serverA.diagnostics)
    }
  }

  final class OTLPHTTPWireNoExportTests: OTLPHTTPWireTestCase {
    func testDisabledAgentSendsNoRequestsAndCreatesNoPersistence() throws {
      let server = LoopbackHTTPTestServer()
      try server.start()
      defer { server.stop() }

      let configuration = AgentConfigBuilder()
        .disableAgent()
        .withExportUrl(URL(string: "http://127.0.0.1:\(server.port)")!)
        .withApiKey(uniqueCredential())
        .build()
      ElasticApmAgent.start(with: configuration)

      XCTAssertNil(
        server.waitForRequest(timeout: Self.zeroRequestWindow) { _ in true },
        server.diagnostics)
      XCTAssertNil(ElasticApmAgent.shared())
      try assertNoPersistence()
    }

    func testUnconfiguredAgentSendsNoRequestsAndCreatesNoPersistence() throws {
      let server = LoopbackHTTPTestServer()
      try server.start()
      defer { server.stop() }

      ElasticApmAgent.start(with: AgentConfigBuilder().build())

      XCTAssertNil(
        server.waitForRequest(timeout: Self.zeroRequestWindow) { _ in true },
        server.diagnostics)
      XCTAssertNil(ElasticApmAgent.shared())
      try assertNoPersistence()
    }
  }

  private enum WireAuthentication {
    case apiKey(String)
    case secretToken(String)

    var headerValue: String {
      switch self {
      case .apiKey(let key):
        return "ApiKey \(key)"
      case .secretToken(let token):
        return "Bearer \(token)"
      }
    }

    func apply(to builder: AgentConfigBuilder) {
      switch self {
      case .apiKey(let key):
        _ = builder.withApiKey(key)
      case .secretToken(let token):
        _ = builder.withSecretToken(token)
      }
    }
  }

  private final class WireTelemetryHarness {
    let authorization: String

    private let server: LoopbackHTTPTestServer
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private let logExporter: LogRecordExporter
    private let persistenceDirectory: URL

    init(server: LoopbackHTTPTestServer, authentication: WireAuthentication) throws {
      self.server = server
      authorization = authentication.headerValue
      persistenceDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("edot-wire-\(UUID().uuidString)", isDirectory: true)

      let builder = AgentConfigBuilder()
        .withExportUrl(URL(string: "http://127.0.0.1:\(server.port)")!)
        .withRemoteManagement(false)
      authentication.apply(to: builder)
      let configuration = builder.build()
      let resource = AgentResource.get().merging(other: AgentEnvResource.get())
      let configManager = AgentConfigManager(
        resource: resource,
        config: configuration,
        instrumentationConfig: InstrumentationConfigBuilder()
          .withPersistentStorageConfiguration(.instantDataDelivery)
          .build())
      let initializer = OpenTelemetryInitializer(
        group: group,
        sessionSampler: SessionSampler { 1.0 },
        exporters: nil,
        persistenceBaseDirectory: persistenceDirectory)

      logExporter = initializer.initializeWithHttp(configManager)
    }

    func emitSpan() {
      let tracer = OpenTelemetry.instance.tracerProvider.get(
        instrumentationName: "OTLPHTTPWireTests")
      tracer.spanBuilder(spanName: "wire-span").startSpan().end()
    }

    func emitLog() {
      OpenTelemetry.instance.loggerProvider
        .loggerBuilder(instrumentationScopeName: "OTLPHTTPWireTests")
        .build()
        .logRecordBuilder()
        .setEventName("wire-log")
        .emit()
    }

    func emitMetric() throws {
      var counter = OpenTelemetry.instance.meterProvider
        .get(name: "OTLPHTTPWireTests")
        .counterBuilder(name: "wire.metric")
        .build()
      counter.add(value: 1)

      let provider = try XCTUnwrap(
        OpenTelemetry.instance.meterProvider as? MeterProviderSdk)
      XCTAssertEqual(provider.forceFlush(), .success)
    }

    func waitForRequest() -> LoopbackHTTPTestServer.Request? {
      server.waitForRequest(timeout: OTLPHTTPWireTestCase.requestTimeout) {
        $0.header(named: "Authorization") == authorization
      }
    }

    var diagnostics: String {
      """
      Expected authorization: \(authorization)
      Providers: tracer=\(type(of: OpenTelemetry.instance.tracerProvider)), \
      logger=\(type(of: OpenTelemetry.instance.loggerProvider)), \
      meter=\(type(of: OpenTelemetry.instance.meterProvider))
      \(server.diagnostics)
      Persistence: \(directoryDiagnostics(at: persistenceDirectory))
      """
    }

    func shutDown() {
      if let tracerProvider = OpenTelemetry.instance.tracerProvider as? TracerProviderSdk {
        tracerProvider.shutdown()
      }
      logExporter.shutdown()
      if let meterProvider = OpenTelemetry.instance.meterProvider as? MeterProviderSdk {
        XCTAssertEqual(meterProvider.shutdown(), .success)
      }
      XCTAssertNoThrow(try group.syncShutdownGracefully())
      XCTAssertNoThrow(try FileManager.default.removeItem(at: persistenceDirectory))
      XCTAssertFalse(FileManager.default.fileExists(atPath: persistenceDirectory.path))
    }
  }

  private extension OTLPHTTPWireTestCase {
    func withWirePipeline(
      authentication: WireAuthentication? = nil,
      _ test: (WireTelemetryHarness) throws -> Void
    ) throws {
      let server = LoopbackHTTPTestServer()
      try server.start()
      let selectedAuthentication = authentication
        ?? .apiKey(uniqueCredential())
      let harness = try WireTelemetryHarness(
        server: server,
        authentication: selectedAuthentication)
      defer {
        harness.shutDown()
        server.stop()
      }

      try test(harness)
    }
  }

  private func directoryDiagnostics(
    at directory: URL,
    fileManager: FileManager = .default
  ) -> String {
    guard fileManager.fileExists(atPath: directory.path) else {
      return "\(directory.path) does not exist"
    }

    do {
      let paths = try fileManager.subpathsOfDirectory(atPath: directory.path).sorted()
      guard !paths.isEmpty else {
        return "\(directory.path) is empty"
      }
      let entries = paths.map { path -> String in
        let url = directory.appendingPathComponent(path)
        do {
          let attributes = try fileManager.attributesOfItem(atPath: url.path)
          let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
          let age = (attributes[.modificationDate] as? Date)
            .map { String(format: "%.1fs old", -$0.timeIntervalSinceNow) }
            ?? "unknown age"
          return "\(path) (\(size) bytes, \(age))"
        } catch {
          return "\(path) (attributes failed: \(error))"
        }
      }
      return "\(directory.path): \(entries.joined(separator: " | "))"
    } catch {
      return "\(directory.path) inspection failed: \(error)"
    }
  }

#endif
