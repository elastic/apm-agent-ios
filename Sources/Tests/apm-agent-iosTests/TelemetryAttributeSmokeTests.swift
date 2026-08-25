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
import ResourceExtension
import XCTest

@testable import ElasticApm

final class ResourceAttributeSmokeTests: XCTestCase {
  func testCompleteResourceOnSpansLogsAndMetrics() throws {
    try withSmokeTelemetry(useLegacyAttributeNames: false) { harness in
      let expected = try expectedResourceAttributes(useLegacyAttributeNames: false)
      harness.emitSpanAndLog()
      let metric = try harness.emitMetric()
      let span = try harness.waitForSpan()
      let log = try harness.waitForLog()

      XCTAssertEqual(span.resource.attributes, expected)
      XCTAssertEqual(log.resource.attributes, expected)
      XCTAssertEqual(metric.resource.attributes, expected)
      XCTAssertNil(span.resource.attributes["service.build"])
      XCTAssertNotEqual(
        span.resource.attributes["telemetry.sdk.version"],
        .string("semver:\(ElasticApmAgent.elasticSwiftAgentVersion)")
      )
    }
  }

  func testCompleteLegacyResourceOnSpansLogsAndMetrics() throws {
    try withSmokeTelemetry(useLegacyAttributeNames: true) { harness in
      let expected = try expectedResourceAttributes(useLegacyAttributeNames: true)
      harness.emitSpanAndLog()
      let metric = try harness.emitMetric()
      let span = try harness.waitForSpan()
      let log = try harness.waitForLog()

      XCTAssertEqual(span.resource.attributes, expected)
      XCTAssertEqual(log.resource.attributes, expected)
      XCTAssertEqual(metric.resource.attributes, expected)
      XCTAssertEqual(
        span.resource.attributes["telemetry.sdk.version"],
        .string("semver:\(ElasticApmAgent.elasticSwiftAgentVersion)")
      )
      XCTAssertNotEqual(
        span.resource.attributes["telemetry.sdk.version"],
        .string(ElasticApmAgent.elasticSwiftAgentVersion)
      )

      let application = ApplicationDataSource()
      if application.build != nil, application.version != nil {
        XCTAssertNotNil(span.resource.attributes["service.build"])
        XCTAssertNil(span.resource.attributes["app.build_id"])
      }
    }
  }
}

final class GlobalSignalAttributeSmokeTests: XCTestCase {
  func testCompleteGlobalAttributesOnSpansAndLogs() throws {
    try withSmokeTelemetry(useLegacyAttributeNames: false) { harness in
      let expectedSessionId = SessionManager.instance.session()
      harness.emitSpanAndLog()
      let span = try harness.waitForSpan()
      let log = try harness.waitForLog()

      XCTAssertEqual(span.attributes["type"], .string("mobile"))
      XCTAssertEqual(span.attributes["session.id"], .string(expectedSessionId))
      XCTAssertEqual(log.attributes["session.id"], .string(expectedSessionId))

      #if os(iOS) && !targetEnvironment(macCatalyst)
        let expectedConnectionType = AttributeValue.string(NetworkStatusManager().status())
        XCTAssertEqual(span.attributes["network.connection.type"], expectedConnectionType)
        XCTAssertEqual(log.attributes["network.connection.type"], expectedConnectionType)
      #endif
    }
  }
}

private final class SmokeTelemetryHarness {
  let spanExporter = WaitingSpanExporter(numberToWaitFor: 1)
  let logExporter = WaitingLogRecordExporter(numberToWaitFor: 1)
  let metricExporter = WaitingMetricExporter(numberToWaitFor: 1)

  private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

  init(useLegacyAttributeNames: Bool) {
    let configuration = AgentConfigBuilder()
      .withExportUrl(URL(string: "https://unused.invalid")!)
      .withRemoteManagement(false)
      .useLegacyAttributeNames(useLegacyAttributeNames)
      .build()
    let resource = AgentResource.get(
      useLegacyAttributeNames: useLegacyAttributeNames
    ).merging(other: AgentEnvResource.get())
    let configManager = AgentConfigManager(
      resource: resource,
      config: configuration,
      instrumentationConfig: InstrumentationConfigBuilder().build())
    let initializer = OpenTelemetryInitializer(
      group: group,
      sessionSampler: SessionSampler { 1.0 },
      exporters: OpenTelemetryInitializer.Exporters(
        metric: metricExporter,
        trace: spanExporter,
        log: logExporter))

    _ = initializer.initializeWithHttp(configManager)
  }

  func emitSpanAndLog() {
    let tracer = OpenTelemetry.instance.tracerProvider.get(
      instrumentationName: "ResourceAttributeSmokeTests")
    let span = tracer.spanBuilder(spanName: "attribute-smoke-span").startSpan()
    span.end()

    let logger = OpenTelemetry.instance.loggerProvider
      .loggerBuilder(instrumentationScopeName: "ResourceAttributeSmokeTests")
      .build()
    logger.logRecordBuilder()
      .setEventName("attribute-smoke-log")
      .emit()
  }

  func waitForSpan() throws -> SpanData {
    try XCTUnwrap(spanExporter.waitForExport()?.first)
  }

  func waitForLog() throws -> ReadableLogRecord {
    try XCTUnwrap(logExporter.waitForExport()?.first)
  }

  func emitMetric() throws -> MetricData {
    var counter = OpenTelemetry.instance.meterProvider
      .get(name: "ResourceAttributeSmokeTests")
      .counterBuilder(name: "attribute.smoke")
      .build()
    counter.add(value: 1)

    let meterProvider = try XCTUnwrap(
      OpenTelemetry.instance.meterProvider as? MeterProviderSdk)
    XCTAssertEqual(meterProvider.forceFlush(), .success)
    return try XCTUnwrap(metricExporter.waitForExport()?.first)
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

private struct DirectorySnapshot: Equatable {
  let exists: Bool
  let contents: Set<String>

  init(at directory: URL, fileManager: FileManager = .default) {
    var isDirectory: ObjCBool = false
    exists = fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
    guard exists,
      let enumerator = fileManager.enumerator(
        at: directory,
        includingPropertiesForKeys: nil)
    else {
      contents = []
      return
    }

    contents = Set(enumerator.compactMap { item in
      guard let url = item as? URL else {
        return nil
      }
      return String(url.path.dropFirst(directory.path.count))
    })
  }
}

private func withSmokeTelemetry(
  useLegacyAttributeNames: Bool,
  _ test: (SmokeTelemetryHarness) throws -> Void
) throws {
  XCTAssertNil(ProcessInfo.processInfo.environment[AgentEnvResource.otelResourceAttributesEnv])
  XCTAssertNil(
    Bundle.main.infoDictionary?[AgentEnvResource.otelResourceAttributesEnv],
    "The smoke tests require an empty OTEL_RESOURCE_ATTRIBUTES overlay")

  let centralConfig = CentralConfig()
  let previousCentralConfig = centralConfig.config
  centralConfig.config = nil

  let cachesDirectory = try FileManager.default.url(
    for: .cachesDirectory,
    in: .userDomainMask,
    appropriateFor: nil,
    create: false)
    .appendingPathComponent("elastic", isDirectory: true)
  let initialCaches = DirectorySnapshot(at: cachesDirectory)
  let harness = SmokeTelemetryHarness(
    useLegacyAttributeNames: useLegacyAttributeNames)

  defer {
    harness.shutDown()
    centralConfig.config = previousCentralConfig
    XCTAssertEqual(
      DirectorySnapshot(at: cachesDirectory),
      initialCaches,
      "Injected exporters must not create agent persistence files")
  }

  try test(harness)
}

private func expectedResourceAttributes(
  useLegacyAttributeNames: Bool
) throws -> [String: AttributeValue] {
  let application = ApplicationDataSource()
  let device = DeviceDataSource()
  let operatingSystem = OperatingSystemDataSource()
  var expected: [String: AttributeValue] = [
    "service.name": .string(
      application.name ?? "unknown_service:\(ProcessInfo.processInfo.processName)"),
    "deployment.environment.name": .string("default"),
    "device.model.identifier": .string(try XCTUnwrap(device.model)),
    "os.type": .string(operatingSystem.type),
    "os.name": .string(operatingSystem.name),
    "os.description": .string(operatingSystem.description),
    "os.version": .string(operatingSystem.version),
    "telemetry.sdk.name": .string("iOS"),
    "telemetry.sdk.language": .string("swift"),
    "telemetry.sdk.version": .string(
      useLegacyAttributeNames
        ? "semver:\(ElasticApmAgent.elasticSwiftAgentVersion)"
        : ElasticApmAgent.elasticSwiftAgentVersion
    ),
    "process.runtime.name": .string(operatingSystem.name),
    "process.runtime.version": .string(operatingSystem.version)
  ]

  if let build = application.build {
    if let version = application.version {
      expected["service.version"] = .string(version)
      expected[useLegacyAttributeNames ? "service.build" : "app.build_id"] =
        .string(build)
    } else {
      expected["service.version"] = .string(build)
    }
  } else if let version = application.version {
    expected["service.version"] = .string(version)
  }

  #if os(macOS)
    XCTAssertNil(device.identifier)
  #else
    expected["device.id"] = .string(try XCTUnwrap(device.identifier))
  #endif

  return expected
}
