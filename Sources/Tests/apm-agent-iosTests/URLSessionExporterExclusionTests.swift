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
  import XCTest

  @testable import ElasticApm

  final class URLSessionExporterExclusionTests: XCTestCase {
    func testExporterRequestsAreExcludedWhileApplicationRequestIsInstrumented() throws {
      let exportServer = LoopbackHTTPTestServer()
      let applicationServer = LoopbackHTTPTestServer()
      try exportServer.start()
      try applicationServer.start()
      defer {
        applicationServer.stop()
        exportServer.stop()
      }

      let exportURLs = [
        exportServer.baseURL,
        exportServer.baseURL.appendingPathComponent("otlp")
      ]
      let harness = URLSessionExclusionHarness(exportURLs: exportURLs)
      defer { harness.shutDown() }

      let seedSpan = try harness.makeSeedSpan()
      for traceEndpoint in harness.traceEndpoints {
        let realExporter = OtlpHttpTraceExporter(
          endpoint: traceEndpoint,
          config: OtlpConfiguration(timeout: 5),
          envVarHeaders: [])
        XCTAssertEqual(realExporter.export(spans: [seedSpan]), .success)
        XCTAssertNotNil(
          exportServer.waitForRequest(timeout: 5) { $0.path == traceEndpoint.path },
          exportServer.diagnostics)
      }

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
    }
  }

  private final class URLSessionExclusionHarness {
    private let spanExporter = WaitingSpanExporter(numberToWaitFor: 1)
    private let logExporter = WaitingLogRecordExporter(numberToWaitFor: 1)
    private let metricExporter = WaitingMetricExporter(numberToWaitFor: 1)
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private let wrapper: InstrumentationWrapper
    let traceEndpoints: [URL]

    init(exportURLs: [URL]) {
      let endpointRegistry = SDKEndpointRegistry()
      let initializer = OpenTelemetryInitializer(
        group: group,
        sessionSampler: SessionSampler { 1.0 },
        exporters: OpenTelemetryInitializer.Exporters(
          metric: metricExporter,
          trace: spanExporter,
          log: logExporter))

      let configManagers = exportURLs.map { exportURL in
        AgentConfigManager(
          resource: Resource(),
          config: AgentConfigBuilder()
            .withExportUrl(exportURL)
            .withRemoteManagement(false)
            .build(),
          instrumentationConfig: InstrumentationConfigBuilder()
            .withLifecycleEvents(false)
            .withViewControllerInstrumentation(false)
            .withSystemMetrics(false)
            .build(),
          endpointRegistry: endpointRegistry)
      }
      for configManager in configManagers {
        _ = initializer.initializeWithHttp(configManager)
      }

      traceEndpoints = exportURLs.map {
        URL(string: $0.absoluteString + "/v1/traces")!
      }
      wrapper = InstrumentationWrapper(config: configManagers[0])
      wrapper.initalize()
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
