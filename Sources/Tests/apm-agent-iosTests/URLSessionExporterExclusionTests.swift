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

// EDOT supports iOS; macOS retains the SwiftPM development loop.
#if os(iOS) || os(macOS)

  import ElasticApmTestSupport
  import Foundation
  import NIO
  import OpenTelemetryApi
  import OpenTelemetryProtocolExporterCommon
  import OpenTelemetryProtocolExporterHttp
  import OpenTelemetrySdk
  import URLSessionInstrumentation
  import XCTest

  @testable import ElasticApm

  final class URLSessionExporterExclusionTests: XCTestCase {
    func testLegacyPollIsExcludedAndDefaultConfigurationDoesNotPoll() throws {
      let enabledServer = LoopbackHTTPTestServer()
      let defaultServer = LoopbackHTTPTestServer()
      try enabledServer.start()
      try defaultServer.start()
      defer {
        defaultServer.stop()
        enabledServer.stop()
      }

      let pollPath = "/otlp/config/v1/agents"
      let firstPollElapsed: TimeInterval
      do {
        let exportURL = enabledServer.baseURL.appendingPathComponent("otlp")
        let harness = URLSessionExclusionHarness(exportURL: exportURL)
        defer { harness.shutDown() }
        let exportInterceptor = ManagementExportInterceptor()

        // Install instrumentation before starting the timer to cover the first poll.
        let start = Date()
        let manager = AgentConfigManager(
          resource: Resource(),
          config: AgentConfigBuilder()
            .withExportUrl(exportURL)
            .withApiKey("synthetic-management-key")
            .withExportHeadersInterceptor(exportInterceptor)
            .withRemoteManagement(true)
            .build(),
          instrumentationConfig: InstrumentationConfigBuilder().build(),
          endpointRegistry: harness.endpointRegistry)
        XCTAssertNotNil(
          enabledServer.waitForRequest(timeout: 5) {
            $0.method == "GET" && $0.path.split(separator: "?").first == Substring(pollPath)
          },
          enabledServer.diagnostics)
        firstPollElapsed = Date().timeIntervalSince(start)
        let pollRequest = try XCTUnwrap(enabledServer.requests.first { $0.method == "GET" })
        XCTAssertEqual(pollRequest.header(named: "Authorization"), "ApiKey synthetic-management-key")
        XCTAssertNil(pollRequest.header(named: "x-custom-export"))
        XCTAssertEqual(exportInterceptor.invocations, 0)

        let legacyManager = try XCTUnwrap(manager.centralConfigManager as? ElasticAgentConfigManager)
        let fetcher = try XCTUnwrap(legacyManager.fetcher)
        let task = try XCTUnwrap(fetcher.fetchQueue.sync { fetcher.task })
        let pollFinished = XCTNSPredicateExpectation(
          predicate: NSPredicate { _, _ in task.state == .completed },
          object: nil)
        wait(for: [pollFinished], timeout: 10)

        let applicationRequest = expectation(description: "application request on the export host")
        URLSession.shared.dataTask(
          with: enabledServer.baseURL.appendingPathComponent("application")
        ) { _, response, error in
          XCTAssertNil(error)
          XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
          applicationRequest.fulfill()
        }.resume()
        wait(for: [applicationRequest], timeout: 10)

        let provider = try XCTUnwrap(OpenTelemetry.instance.tracerProvider as? TracerProviderSdk)
        provider.forceFlush()
        let spans = try XCTUnwrap(harness.waitForInstrumentedSpans())
        let pollSpans = spans.filter {
          $0.targets(server: enabledServer)
            && $0.attributes[SemanticConventions.Url.path.rawValue]?.description == pollPath
        }
        XCTAssertTrue(pollSpans.isEmpty, "Legacy poll requests produced spans: \(pollSpans)")
        XCTAssertEqual(
          spans.filter {
            $0.kind == .client && $0.targets(server: enabledServer)
              && $0.attributes[SemanticConventions.Url.path.rawValue]?.description == "/application"
          }.count,
          1,
          "Ordinary application traffic on the export host must remain instrumented: \(spans)")
      }

      let harness = URLSessionExclusionHarness(
        exportURL: defaultServer.baseURL.appendingPathComponent("otlp"))
      defer { harness.shutDown() }
      XCTAssertNil(
        defaultServer.waitForRequest(timeout: max(1, firstPollElapsed + 0.5)) {
          $0.path.split(separator: "?").first == Substring(pollPath)
        },
        "Default configuration started a legacy poll: \(defaultServer.diagnostics)")
    }

    func testOpampPreservesManagementAuthAndDoesNotInvokeExportInterceptorOrProduceSpans() throws {
      let server = LoopbackHTTPTestServer()
      try server.start()
      defer { server.stop() }
      let harness = URLSessionExclusionHarness(exportURL: server.baseURL.appendingPathComponent("otlp"))
      defer { harness.shutDown() }
      let interceptor = ManagementExportInterceptor()
      let manager = AgentConfigManager(
        resource: Resource(),
        config: AgentConfigBuilder()
          .withExportUrl(server.baseURL.appendingPathComponent("otlp"))
          .withManagementUrl(server.baseURL.appendingPathComponent("v1/opamp"))
          .withApiKey("synthetic-opamp-key")
          .withExportHeadersInterceptor(interceptor)
          .useOpAMP()
          .build(),
        instrumentationConfig: InstrumentationConfigBuilder().build(),
        endpointRegistry: harness.endpointRegistry)
      try withExtendedLifetime(manager) {
        let request = try XCTUnwrap(server.waitForRequest(timeout: 10) { $0.path == "/v1/opamp" })
        XCTAssertEqual(request.header(named: "Authorization"), "ApiKey synthetic-opamp-key")
        XCTAssertNil(request.header(named: "x-custom-export"))
        XCTAssertEqual(interceptor.invocations, 0)
        let application = expectation(description: "application request beside OpAMP")
        URLSession.shared.dataTask(with: server.baseURL.appendingPathComponent("application")) { _, _, error in
          XCTAssertNil(error)
          application.fulfill()
        }.resume()
        wait(for: [application], timeout: 10)
        (OpenTelemetry.instance.tracerProvider as? TracerProviderSdk)?.forceFlush()
        let spans = try XCTUnwrap(harness.waitForInstrumentedSpans())
        XCTAssertTrue(spans.contains { $0.attributes[SemanticConventions.Url.path.rawValue]?.description == "/application" })
        XCTAssertFalse(spans.contains { $0.attributes[SemanticConventions.Url.path.rawValue]?.description == "/v1/opamp" })
        XCTAssertEqual(interceptor.invocations, 0)
      }
    }

    func testExporterRequestsAreExcludedWhileApplicationRequestIsInstrumented() throws {
      let exportServer = LoopbackHTTPTestServer()
      let applicationServer = LoopbackHTTPTestServer()
      try exportServer.start()
      try applicationServer.start()
      defer {
        applicationServer.stop()
        exportServer.stop()
      }

      let exportURL =
        URL(string: exportServer.baseURL.appendingPathComponent("otlp").absoluteString + "/")!
      let harness = URLSessionExclusionHarness(exportURL: exportURL)
      defer { harness.shutDown() }

      let seedSpan = try harness.makeSeedSpan()
      let exportInterceptor = ManagementExportInterceptor()
      let exportConfiguration = AgentConfigBuilder()
        .withApiKey("synthetic-export-key")
        .withExportHeadersInterceptor(exportInterceptor)
        .build()
      let realExporter = OtlpHttpTraceExporter(
        endpoint: harness.traceEndpoint,
        config: ExportHeadersProvider(exportConfiguration).configuration,
        envVarHeaders: nil)
      XCTAssertEqual(realExporter.export(spans: [seedSpan]), .success)
      XCTAssertNotNil(
        exportServer.waitForRequest(timeout: 5) { $0.path == harness.traceEndpoint.path },
        exportServer.diagnostics)
      XCTAssertEqual(exportServer.requests.first?.header(named: "x-custom-export"), "synthetic-export-only")
      XCTAssertEqual(exportInterceptor.invocations, 1)

      let requestExpectation = expectation(description: "ordinary application request")
      URLSession.shared.dataTask(
        with: applicationServer.baseURL.appendingPathComponent("application")
      ) { _, response, error in
        XCTAssertNil(error)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        requestExpectation.fulfill()
      }.resume()
      wait(for: [requestExpectation], timeout: 10)

      let spans = try XCTUnwrap(
        harness.waitForInstrumentedSpans(),
        """
        No URLSession spans were exported.
        Export server: \(exportServer.diagnostics)
        Application server: \(applicationServer.diagnostics)
        """)
      let exporterSpans = spans.filter {
        $0.targets(server: exportServer)
      }
      XCTAssertTrue(
        exporterSpans.isEmpty,
        "Exporter requests produced spans: \(exporterSpans)")

      let applicationSpans = spans.filter {
        $0.kind == .client
          && $0.targets(server: applicationServer)
          && $0.attributes[SemanticConventions.Url.path.rawValue]?.description == "/application"
      }
      XCTAssertEqual(
        applicationSpans.count,
        1,
        "Expected exactly one application client span, got: \(spans)")
      let applicationSpan = try XCTUnwrap(applicationSpans.first)
      XCTAssertEqual(
        applicationSpan.attributes[
          SemanticConventions.Http.responseStatusCode.rawValue
        ]?.description,
        "200")

      let unavailableServer = LoopbackHTTPTestServer()
      try unavailableServer.start()
      let unavailableURL = unavailableServer.baseURL.appendingPathComponent("unavailable")
      unavailableServer.stop()

      let failureExpectation = expectation(description: "failed application request")
      URLSession.shared.dataTask(with: unavailableURL) { _, response, error in
        XCTAssertNil(response)
        XCTAssertNotNil(error)
        failureExpectation.fulfill()
      }.resume()
      wait(for: [failureExpectation], timeout: 10)

      let failureSpans = try XCTUnwrap(
        harness.waitForInstrumentedSpans(),
        "No failed URLSession span was exported for \(unavailableURL)")
        .filter {
          $0.kind == .client && $0.targets(server: unavailableServer)
        }
      let failureSpan = try XCTUnwrap(
        failureSpans.first,
        "Expected one failed client span, got: \(failureSpans)")
      XCTAssertEqual(failureSpans.count, 1)
      guard case .error = failureSpan.status else {
        return XCTFail("Expected failed client span status to be Error")
      }
      XCTAssertNil(
        failureSpan.attributes[SemanticConventions.Http.responseStatusCode.rawValue])
      let errorType = try XCTUnwrap(
        failureSpan.attributes[SemanticConventions.Error.type.rawValue]?.description)
      let exception = try XCTUnwrap(
        failureSpan.events.first {
          $0.name == SemanticConventions.Exception.exception.rawValue
        })
      XCTAssertEqual(
        exception.attributes[SemanticConventions.Exception.type.rawValue]?.description,
        errorType)
    }
  }

  private final class ManagementExportInterceptor: Interceptor {
    private let lock = NSLock()
    private var count = 0
    var invocations: Int {
      lock.lock()
      defer { lock.unlock() }
      return count
    }
    func intercept(_ headers: [String: String]) -> [String: String] {
      lock.lock()
      count += 1
      lock.unlock()
      var output = headers
      output["x-custom-export"] = "synthetic-export-only"
      return output
    }
  }

  private final class URLSessionExclusionHarness {
    private static var instrumentation: URLSessionInstrumentation?
    private let spanExporter = WaitingSpanExporter(numberToWaitFor: 1)
    private let logExporter = WaitingLogRecordExporter(numberToWaitFor: 1)
    private let metricExporter = WaitingMetricExporter(numberToWaitFor: 1)
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private let wrapper: InstrumentationWrapper
    let endpointRegistry = SDKEndpointRegistry()
    let traceEndpoint: URL

    init(exportURL: URL) {
      let initializer = OpenTelemetryInitializer(
        group: group,
        sessionSampler: SessionSampler { 1.0 },
        exporters: OpenTelemetryInitializer.Exporters(
          metric: metricExporter,
          trace: spanExporter,
          log: logExporter))

      let configManager = AgentConfigManager(
        resource: Resource(),
        config: AgentConfigBuilder()
          .withExportUrl(exportURL)
          .build(),
        instrumentationConfig: InstrumentationConfigBuilder()
          .withLifecycleEvents(false)
          .withViewControllerInstrumentation(false)
          .withSystemMetrics(false)
          .build(),
        endpointRegistry: endpointRegistry)
      _ = initializer.initializeWithHttp(configManager)

      traceEndpoint = URL(string: exportURL.absoluteString + "/v1/traces")!
      wrapper = InstrumentationWrapper(config: configManager)
      // Upstream installs once per process; subsequent harnesses update that instance.
      if let instrumentation = Self.instrumentation {
        instrumentation.configuration = wrapper.makeURLSessionInstrumentationConfiguration()
      } else {
        wrapper.initalize()
        Self.instrumentation = wrapper.urlSessionInstrumentation
      }
    }

    func makeSeedSpan() throws -> SpanData {
      let tracer = OpenTelemetry.instance.tracerProvider.get(
        instrumentationName: "URLSessionExporterExclusionTests")
      tracer.spanBuilder(spanName: "export-seed").startSpan().end()
      let provider = try XCTUnwrap(
        OpenTelemetry.instance.tracerProvider as? TracerProviderSdk)
      provider.forceFlush()
      return try XCTUnwrap(spanExporter.waitForExport()?.first)
    }

    func waitForInstrumentedSpans() -> [SpanData]? {
      spanExporter.waitForExport()
    }

    func shutDown() {
      if let tracerProvider = OpenTelemetry.instance.tracerProvider as? TracerProviderSdk {
        tracerProvider.shutdown()
      }
      if let meterProvider = OpenTelemetry.instance.meterProvider as? MeterProviderSdk {
        XCTAssertEqual(meterProvider.shutdown(), .success)
      }
      XCTAssertNoThrow(try group.syncShutdownGracefully())
    }
  }

  private extension SpanData {
    func targets(server: LoopbackHTTPTestServer) -> Bool {
      if let full = attributes[SemanticConventions.Url.full.rawValue]?.description,
         let url = URL(string: full),
         url.host == server.baseURL.host,
         url.port == server.port {
        return true
      }

      return attributes[SemanticConventions.Server.address.rawValue]?.description
        == server.baseURL.host
        && attributes[SemanticConventions.Server.port.rawValue]?.description
          == String(server.port)
    }
  }

#endif
