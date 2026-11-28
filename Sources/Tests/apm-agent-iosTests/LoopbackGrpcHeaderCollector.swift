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

// Test-only OTLP collector for ExportHeadersTests. Always binds an ephemeral loopback port;
// it has no production endpoint or credential configuration. iOS is supported, with macOS
// retaining the SwiftPM development loop; other platforms do not run wire fixtures.
#if os(iOS) || os(macOS)
import Foundation
import GRPC
import NIO
import OpenTelemetryProtocolExporterCommon
import OpenTelemetryProtocolExporterGrpc

final class LoopbackGrpcHeaderCollector {
  struct Request {
    let signal: String
    let headers: [(String, String)]
    let body: Data
  }

  private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
  private let lock = NSLock()
  private var captured: [Request] = []
  private var server: Server?

  var requests: [Request] {
    lock.lock()
    defer { lock.unlock() }
    return captured
  }

  var port: Int { server?.channel.localAddress?.port ?? 0 }

  func start() throws {
    server = try Server.insecure(group: group)
      .withServiceProviders([TraceService(self), LogService(self), MetricService(self)])
      .bind(host: "127.0.0.1", port: 0).wait()
  }

  func stop() throws {
    try server?.close().wait()
    server = nil
    try group.syncShutdownGracefully()
  }

  private func record(_ signal: String, context: StatusOnlyCallContext, body: Data) {
    lock.lock()
    defer { lock.unlock() }
    captured.append(Request(signal: signal, headers: context.headers.map { ($0.name, $0.value) }, body: body))
  }

  private final class TraceService: Opentelemetry_Proto_Collector_Trace_V1_TraceServiceProvider {
    let owner: LoopbackGrpcHeaderCollector
    var interceptors: Opentelemetry_Proto_Collector_Trace_V1_TraceServiceServerInterceptorFactoryProtocol? { nil }
    init(_ owner: LoopbackGrpcHeaderCollector) { self.owner = owner }

    func export(
      request: Opentelemetry_Proto_Collector_Trace_V1_ExportTraceServiceRequest,
      context: StatusOnlyCallContext
    ) -> EventLoopFuture<Opentelemetry_Proto_Collector_Trace_V1_ExportTraceServiceResponse> {
      owner.record("traces", context: context, body: (try? request.serializedData()) ?? Data())
      return context.eventLoop.makeSucceededFuture(.init())
    }
  }

  private final class LogService: Opentelemetry_Proto_Collector_Logs_V1_LogsServiceProvider {
    let owner: LoopbackGrpcHeaderCollector
    var interceptors: Opentelemetry_Proto_Collector_Logs_V1_LogsServiceServerInterceptorFactoryProtocol? { nil }
    init(_ owner: LoopbackGrpcHeaderCollector) { self.owner = owner }

    func export(
      request: Opentelemetry_Proto_Collector_Logs_V1_ExportLogsServiceRequest,
      context: StatusOnlyCallContext
    ) -> EventLoopFuture<Opentelemetry_Proto_Collector_Logs_V1_ExportLogsServiceResponse> {
      owner.record("logs", context: context, body: (try? request.serializedData()) ?? Data())
      return context.eventLoop.makeSucceededFuture(.init())
    }
  }

  private final class MetricService: Opentelemetry_Proto_Collector_Metrics_V1_MetricsServiceProvider {
    let owner: LoopbackGrpcHeaderCollector
    var interceptors: Opentelemetry_Proto_Collector_Metrics_V1_MetricsServiceServerInterceptorFactoryProtocol? { nil }
    init(_ owner: LoopbackGrpcHeaderCollector) { self.owner = owner }

    func export(
      request: Opentelemetry_Proto_Collector_Metrics_V1_ExportMetricsServiceRequest,
      context: StatusOnlyCallContext
    ) -> EventLoopFuture<Opentelemetry_Proto_Collector_Metrics_V1_ExportMetricsServiceResponse> {
      owner.record("metrics", context: context, body: (try? request.serializedData()) ?? Data())
      return context.eventLoop.makeSucceededFuture(.init())
    }
  }
}
#endif
