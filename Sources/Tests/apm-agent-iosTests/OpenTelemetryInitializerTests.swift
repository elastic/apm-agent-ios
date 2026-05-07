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

import Foundation
import NIO
import OpenTelemetryApi
import OpenTelemetrySdk
import XCTest
@testable import ElasticApm

final class OpenTelemetryInitializerTests: XCTestCase {
  private var group: MultiThreadedEventLoopGroup!

  override func setUp() {
    super.setUp()
    group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
  }

  override func tearDown() {
    try? group?.syncShutdownGracefully()
    group = nil
    super.tearDown()
  }

  func testLogLabel() {
    XCTAssertEqual(OpenTelemetryInitializer.logLabel, "Elastic-OTLP-Exporter")
  }

  func testCreatePersistenceFolderCreatesElasticCachesDirectory() throws {
    guard let folder = OpenTelemetryInitializer.createPersistenceFolder() else {
      XCTFail("expected persistence folder URL")
      return
    }

    XCTAssertEqual(folder.lastPathComponent, "elastic")

    var isDir: ObjCBool = false
    XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir))
    XCTAssertTrue(isDir.boolValue)

    let caches = try? FileManager.default.url(
      for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false
    )
    XCTAssertNotNil(caches)
    XCTAssertTrue(try folder.path.hasPrefix(XCTUnwrap(caches?.path)))
  }

  func testCreatePersistenceFolderReturnsSameLocationOnRepeatedCalls() {
    let first = OpenTelemetryInitializer.createPersistenceFolder()
    let second = OpenTelemetryInitializer.createPersistenceFolder()
    XCTAssertEqual(first?.standardizedFileURL, second?.standardizedFileURL)
  }

  func testInitRetainsEventLoopGroupAndSessionSampler() {
    let sampler = SessionSampler { 1.0 }
    let initializer = OpenTelemetryInitializer(group: group, sessionSampler: sampler)
    XCTAssertTrue(initializer.group as AnyObject === group as AnyObject)
    XCTAssertTrue(initializer.sessionSampler === sampler)
  }

  func testInitializeWithHttpProducesRealLogExporterWhenCollectorUrlConfigured() {
    let initializer = OpenTelemetryInitializer(group: group, sessionSampler: SessionSampler { 1.0 })
    let resource = AgentResource.get().merging(other: AgentEnvResource.get())
    let configManager = AgentConfigManager(
      resource: resource,
      config: AgentConfiguration(),
      instrumentationConfig: InstrumentationConfiguration()
    )

    let exporter = initializer.initializeWithHttp(configManager)

    XCTAssertFalse(exporter as AnyObject === NoopLogRecordExporter.instance as AnyObject)
  }

  func testInitializeGrpcReturnsLogExporter() {
    let initializer = OpenTelemetryInitializer(group: group, sessionSampler: SessionSampler { 1.0 })
    let resource = AgentResource.get().merging(other: AgentEnvResource.get())
    let configManager = AgentConfigManager(
      resource: resource,
      config: AgentConfiguration(),
      instrumentationConfig: InstrumentationConfiguration()
    )

    let exporter = initializer.initialize(configManager)

    XCTAssertFalse(exporter as AnyObject === NoopLogRecordExporter.instance as AnyObject)
  }

  func testInitializeWithHttpExposesMetricExporterAndResource() {
    let initializer = OpenTelemetryInitializer(group: group, sessionSampler: SessionSampler { 1.0 })
    let resource = AgentResource.get().merging(other: AgentEnvResource.get())
    let configManager = AgentConfigManager(
      resource: resource,
      config: AgentConfiguration(),
      instrumentationConfig: InstrumentationConfiguration()
    )

    _ = initializer.initializeWithHttp(configManager)

    XCTAssertNotNil(initializer.metricExporter)
    XCTAssertNotNil(initializer.resource)
  }

  func testInitializeGrpcExposesMetricExporterAndResource() {
    let initializer = OpenTelemetryInitializer(group: group, sessionSampler: SessionSampler { 1.0 })
    let resource = AgentResource.get().merging(other: AgentEnvResource.get())
    let configManager = AgentConfigManager(
      resource: resource,
      config: AgentConfiguration(),
      instrumentationConfig: InstrumentationConfiguration()
    )

    _ = initializer.initialize(configManager)

    XCTAssertNotNil(initializer.metricExporter)
    XCTAssertNotNil(initializer.resource)
    XCTAssertEqual(initializer.metricExportInterval, 60.0)
  }

  func testInitializeWithHttpUsesConfiguredMetricExportInterval() {
    var agentConfig = AgentConfiguration()
    agentConfig.metricExportInterval = 30.0
    let initializer = OpenTelemetryInitializer(group: group, sessionSampler: SessionSampler { 1.0 })
    let resource = AgentResource.get().merging(other: AgentEnvResource.get())
    let configManager = AgentConfigManager(
      resource: resource,
      config: agentConfig,
      instrumentationConfig: InstrumentationConfiguration()
    )

    _ = initializer.initializeWithHttp(configManager)

    XCTAssertEqual(initializer.metricExportInterval, 30.0)
  }

  func testAgentConfigBuilderAppliesMetricExportInterval() {
    let config = AgentConfigBuilder()
      .withMetricExportInterval(45.0)
      .build()

    XCTAssertEqual(config.metricExportInterval, 45.0)
  }
}
