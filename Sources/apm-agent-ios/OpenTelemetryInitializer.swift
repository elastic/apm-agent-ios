// Copyright © 2022 Elasticsearch BV
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
import GRPC
import Logging
import NIO
import OpenTelemetryApi
import OpenTelemetryProtocolExporterCommon
import OpenTelemetryProtocolExporterGrpc
import OpenTelemetrySdk
import PersistenceExporter

class OpenTelemetryInitializer {
  static let logLabel = "Elastic-OTLP-Exporter"

  static func createPersistenceFolder() -> URL? {
    do {
      let cachesDir = try FileManager.default.url(
        for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      let persistentDir = cachesDir.appendingPathComponent("elastic")
      try FileManager.default.createDirectory(at: persistentDir, withIntermediateDirectories: true)
      return persistentDir
    } catch {
      return nil
    }
  }

  static func initialize(_ configuration: AgentConfigManager) -> EventLoopGroup {
    let otlpConfiguration = OtlpConfiguration(
      timeout: OtlpConfiguration.DefaultTimeoutInterval,
      headers: OpenTelemetryHelper.generateExporterHeaders(configuration.agent.auth))
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let channel = OpenTelemetryHelper.getChannel(with: configuration.agent, group: group)

    let resources = AgentResource.get().merging(other: AgentEnvResource.get())
    let metricExporter = {
      let defaultExporter = OtlpMetricExporter(
        channel: channel, config: otlpConfiguration, logger: Logger(label: Self.logLabel))
      do {
        if let path = createPersistenceFolder() {
          return try PersistenceMetricExporterDecorator(
            metricExporter: defaultExporter, storageURL: path) as MetricExporter
        }
      } catch {}
      return defaultExporter as MetricExporter
    }()

    let traceExporter = {
      let defaultExporter = OtlpTraceExporter(
        channel: channel, config: otlpConfiguration, logger: Logger(label: Self.logLabel))
      do {
        if let path = createPersistenceFolder() {
          return try PersistenceSpanExporterDecorator(
            spanExporter: OtlpTraceExporter(
              channel: channel, config: otlpConfiguration, logger: Logger(label: Self.logLabel)),
            storageURL: path) as SpanExporter
        }
      } catch {}
      return defaultExporter as SpanExporter

    }()
    let logExporter = {
      let defaultExporter = OtlpLogExporter(
        channel: channel, config: otlpConfiguration, logger: Logger(label: Self.logLabel))
      do {
        if let path = createPersistenceFolder() {
          return try PersistenceLogExporterDecorator(
            logRecordExporter: OtlpLogExporter(
              channel: channel, config: otlpConfiguration, logger: Logger(label: Self.logLabel)),
            storageURL: path) as LogRecordExporter
        }
      } catch {}
      return defaultExporter as LogRecordExporter
    }()

    // initialize meter provider

    OpenTelemetry.registerMeterProvider(
      meterProvider: MeterProviderBuilder()
        .with(processor: ElasticMetricProcessor(configuration.agent.metricFilters))
        .with(resource: resources)
        .with(exporter: metricExporter)
        .build())

    // initialize trace provider
    OpenTelemetry.registerTracerProvider(
      tracerProvider: TracerProviderBuilder()
        .add(
          spanProcessor: ElasticSpanProcessor(
            spanExporter: traceExporter,
            configuration.agent.spanFilters)
        )
        .with(resource: resources)
        .with(clock: NTPClock())
        .build())

    OpenTelemetry.registerLoggerProvider(
      loggerProvider: LoggerProviderBuilder()
        .with(clock: NTPClock())
        .with(resource: resources)
        .with(processors: [
          ElasticLogRecordProcessor(
            logRecordExporter: logExporter,
            configuration.agent.logFilters)
        ])
        .build())

    return group
  }

}
