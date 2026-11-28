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

// Real wire fixtures run on supported iOS and the macOS SwiftPM development loop.
#if os(iOS) || os(macOS)
import ElasticApmTestSupport
import Foundation
import NIO
import OpenTelemetryApi
import OpenTelemetrySdk
import PersistenceExporter
import XCTest

@testable import ElasticApm

final class ExportHeadersTests: XCTestCase {
  func testRotationAcrossEverySignalAndTransportAndSecondSetterReplacesFirst() throws {
    for transport in HeaderWirePipeline.Transport.allCases {
      let credentials = HeaderSnapshot(["authorization": "ApiKey synthetic-first", "x-generation": "first"])
      let discarded = HeaderSnapshot([:])
      let pipeline = try HeaderWirePipeline(transport: transport) { builder in
        builder.withApiKey("synthetic-built-in")
          .withExportHeadersInterceptor(ClosureInterceptor(discarded.replacingAuthorization))
          .withExportHeadersInterceptor(ClosureInterceptor(credentials.replacingAuthorization))
      }
      defer { pipeline.stop() }

      try pipeline.exportCycle()
      try assertSignals(pipeline, since: 0, authorization: "ApiKey synthetic-first", generation: "first")
      let firstCount = pipeline.requests.count
      credentials.update(["authorization": "ApiKey synthetic-second", "x-generation": "second"])
      try pipeline.exportCycle()
      try assertSignals(pipeline, since: firstCount, authorization: "ApiKey synthetic-second", generation: "second")
      XCTAssertEqual(discarded.invocations, 0)
      XCTAssertGreaterThanOrEqual(credentials.invocations, 6)
      XCTAssertTrue(credentials.inputs.allSatisfy { $0["Authorization"] == "ApiKey synthetic-built-in" })
      XCTAssertTrue(credentials.inputs.allSatisfy { $0["x-generation"] == nil }, "Each callback gets a fresh generated map")
    }
  }

  func testAdditionalHeadersPreserveBuiltInApiKeyAuth() throws {
    for transport in HeaderWirePipeline.Transport.allCases {
      let pipeline = try HeaderWirePipeline(transport: transport) { builder in
        builder.withApiKey("synthetic-api")
          .withExportHeadersInterceptor(ClosureInterceptor { input in
            var output = input
            output["x-custom"] = "synthetic-extra"
            return output
          })
      }
      defer { pipeline.stop() }
      try pipeline.exportCycle()
      try assertSignals(pipeline, authorization: "ApiKey synthetic-api")
      for request in pipeline.requests {
        XCTAssertEqual(request.header("x-custom"), "synthetic-extra")
      }
    }
  }

  func testNoInterceptorAndIdentityPreserveGeneratedHeaders() throws {
    for transport in HeaderWirePipeline.Transport.allCases {
      for identity in [false, true] {
        let pipeline = try HeaderWirePipeline(transport: transport) { builder in
          _ = builder.withApiKey("synthetic-preserved")
          return identity ? builder.withExportHeadersInterceptor(ClosureInterceptor { $0 }) : builder
        }
        defer { pipeline.stop() }
        try pipeline.exportCycle()
        try assertSignals(pipeline, authorization: "ApiKey synthetic-preserved")
      }
    }
  }

  func testRemovalAndEmptyResultRemoveAuthorization() throws {
    for transport in HeaderWirePipeline.Transport.allCases {
      for empty in [false, true] {
        let pipeline = try HeaderWirePipeline(transport: transport) { builder in
          builder.withSecretToken("synthetic-removed")
            .withExportHeadersInterceptor(ClosureInterceptor { input in
              empty ? [:] : input.filter { $0.key.caseInsensitiveCompare("authorization") != .orderedSame }
            })
        }
        defer { pipeline.stop() }
        try pipeline.exportCycle()
        try assertSignals(pipeline, authorization: nil)
      }
    }
  }

  func testPersistenceReplayUsesCurrentCredentials() throws {
    for transport in HeaderWirePipeline.Transport.allCases {
      let credentials = HeaderSnapshot(["authorization": "ApiKey synthetic-queued-secret"])
      let pipeline = try HeaderWirePipeline(transport: transport, deferredReplay: true) {
        $0.withExportHeadersInterceptor(ClosureInterceptor(credentials.replacingAuthorization))
      }
      defer { pipeline.stop() }
      // The initial disk-worker delay lets all three configured exporters persist their batches
      // before any header resolution or network call. Flush only processors, not the log exporter.
      try pipeline.exportCycle(flushLogs: false)
      XCTAssertTrue(pipeline.requests.isEmpty)
      XCTAssertEqual(credentials.invocations, 0)
      let count = pipeline.requests.count
      credentials.update(["authorization": "ApiKey synthetic-replayed-secret"])
      XCTAssertTrue(pipeline.waitForSignals(since: count), "Queued signals did not replay: \(pipeline.requests)")
      try assertSignals(pipeline, since: count, authorization: "ApiKey synthetic-replayed-secret")
    }
  }

  private func assertSignals(
    _ pipeline: HeaderWirePipeline,
    since count: Int = 0,
    authorization: String?,
    generation: String? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    XCTAssertTrue(pipeline.waitForSignals(since: count), "Missing signal: \(pipeline.requests)", file: file, line: line)
    let requests = Array(pipeline.requests.dropFirst(count))
    XCTAssertEqual(Set(requests.map(\.signal)), Set(HeaderWirePipeline.signals), file: file, line: line)
    for request in requests {
      XCTAssertEqual(request.header("authorization"), authorization, file: file, line: line)
      XCTAssertEqual(request.names.filter { $0.lowercased() == "authorization" }.count,
                     authorization == nil ? 0 : 1, file: file, line: line)
      if let generation { XCTAssertEqual(request.header("x-generation"), generation, file: file, line: line) }
      XCTAssertFalse(request.body.isEmpty, file: file, line: line)
    }
  }
}

private final class HeaderSnapshot {
  private let lock = NSLock()
  private var headers: [String: String]
  private var capturedInputs: [[String: String]] = []

  init(_ headers: [String: String]) { self.headers = headers }

  var inputs: [[String: String]] {
    lock.lock()
    defer { lock.unlock() }
    return capturedInputs
  }
  var invocations: Int { inputs.count }

  func update(_ value: [String: String]) {
    lock.lock()
    headers = value
    lock.unlock()
  }

  func replacingAuthorization(_ generated: [String: String]) -> [String: String] {
    lock.lock()
    defer { lock.unlock() }
    capturedInputs.append(generated)
    return generated.filter { $0.key.lowercased() != "authorization" }
      .merging(headers) { _, new in new }
  }
}

private final class HeaderWirePipeline {
  enum Transport: CaseIterable { case http, grpc }
  static let signals = ["traces", "logs", "metrics"]
  struct Request {
    let signal: String
    let headers: [(String, String)]
    let names: [String]
    let body: Data
    func header(_ name: String) -> String? { headers.first { $0.0.lowercased() == name.lowercased() }?.1 }
  }

  let storage = FileManager.default.temporaryDirectory.appendingPathComponent("edot-headers-\(UUID().uuidString)")
  private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
  private let http = LoopbackHTTPTestServer()
  private let grpc = LoopbackGrpcHeaderCollector()
  private let transport: Transport
  private let logExporter: LogRecordExporter
  private var stopped = false

  init(
    transport: Transport,
    deferredReplay: Bool = false,
    configure: (AgentConfigBuilder) -> AgentConfigBuilder
  ) throws {
    self.transport = transport
    let endpoint: URL
    switch transport {
    case .http:
      try http.start()
      endpoint = http.baseURL
    case .grpc:
      try grpc.start()
      endpoint = try XCTUnwrap(URL(string: "http://127.0.0.1:\(grpc.port)"))
    }
    let config = configure(AgentConfigBuilder().withExportUrl(endpoint).useConnectionType(
      transport == .http ? .http : .grpc)).build()
    let manager = AgentConfigManager(
      resource: Resource(), config: config,
      instrumentationConfig: InstrumentationConfigBuilder().withPersistentStorageConfiguration(
        PersistencePerformancePreset(
          maxFileSize: 1_048_576, maxDirectorySize: 4_194_304,
          maxFileAgeForWrite: 0, minFileAgeForRead: 0,
          maxFileAgeForRead: 3600, maxObjectsInFile: 100, maxObjectSize: 1_048_576,
          synchronousWrite: true, initialExportDelay: deferredReplay ? 2 : 0.1,
          defaultExportDelay: 0.1, minExportDelay: 0.1, maxExportDelay: 0.1,
          exportDelayChangeRate: 0)).build())
    let initializer = OpenTelemetryInitializer(
      group: group, sessionSampler: SessionSampler { 1 }, persistenceBaseDirectory: storage)
    logExporter = transport == .http ? initializer.initializeWithHttp(manager) : initializer.initialize(manager)
  }

  var requests: [Request] {
    switch transport {
    case .http:
      return http.requests.map {
        Request(signal: String($0.path.dropFirst("/v1/".count)), headers: Array($0.headers),
                names: $0.headerNames, body: $0.body)
      }
    case .grpc:
      return grpc.requests.map {
        Request(signal: $0.signal, headers: $0.headers, names: $0.headers.map(\.0), body: $0.body)
      }
    }
  }

  func exportCycle(flushLogs: Bool = true) throws {
    for signal in Self.signals { emitAndFlush(signal, flushLogs: flushLogs) }
  }

  func createSpan() {
    OpenTelemetry.instance.tracerProvider.get(instrumentationName: "ExportHeadersTests")
      .spanBuilder(spanName: "synthetic-header-span").startSpan().end()
  }

  func emitAndFlush(_ signal: String, flushLogs: Bool = true) {
    switch signal {
    case "traces":
      createSpan()
      (OpenTelemetry.instance.tracerProvider as? TracerProviderSdk)?.forceFlush()
    case "logs":
      let log = ReadableLogRecord(
        resource: Resource(), instrumentationScopeInfo: InstrumentationScopeInfo(name: "ExportHeadersTests"),
        timestamp: Date(), body: .string("synthetic-header-log"), attributes: [:])
      XCTAssertEqual(logExporter.export(logRecords: [log]), .success)
      if flushLogs { _ = logExporter.forceFlush() }
    default:
      var counter = OpenTelemetry.instance.meterProvider.get(name: "ExportHeadersTests")
        .counterBuilder(name: "synthetic.header.counter").build()
      counter.add(value: 1)
      _ = (OpenTelemetry.instance.meterProvider as? MeterProviderSdk)?.forceFlush()
    }
  }

  func waitForSignals(since count: Int = 0) -> Bool {
    let deadline = Date().addingTimeInterval(10)
    repeat {
      if Set(requests.dropFirst(count).map(\.signal)) == Set(Self.signals) { return true }
      Thread.sleep(forTimeInterval: 0.02)
    } while Date() < deadline
    return false
  }

  func stop() {
    guard !stopped else { return }
    stopped = true
    (OpenTelemetry.instance.tracerProvider as? TracerProviderSdk)?.shutdown()
    logExporter.shutdown()
    _ = (OpenTelemetry.instance.meterProvider as? MeterProviderSdk)?.shutdown()
    http.stop()
    XCTAssertNoThrow(try grpc.stop())
    XCTAssertNoThrow(try group.syncShutdownGracefully())
    try? FileManager.default.removeItem(at: storage)
  }
}
#endif
