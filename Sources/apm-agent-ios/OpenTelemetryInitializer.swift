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
import OpenTelemetryProtocolExporterHttp
import OpenTelemetrySdk
import PersistenceExporter
import os


class OpenTelemetryInitializer {
  static let logLabel = "Elastic-OTLP-Exporter"
  
  let group: EventLoopGroup
  let sessionSampler: SessionSampler
  
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
  
  
  
  init(group: EventLoopGroup, sessionSampler: SessionSampler) {
    self.group = group
    self.sessionSampler = sessionSampler
  }
  
  // swiftlint:disable:next function_body_length
  func initialize(_ configuration: AgentConfigManager) {
    
    var traceSampleFilter: [SignalFilter<ReadableSpan>] = [
      SignalFilter<ReadableSpan>({ [self] _ in
        self.sessionSampler.shouldSample
      })
    ]
    
    var logSampleFliter: [SignalFilter<ReadableLogRecord>] = [
      SignalFilter<ReadableLogRecord>({ [self] _ in
        self.sessionSampler.shouldSample
      })
    ]
    
    var metricSampleFilter: [SignalFilter<Metric>] = [
      SignalFilter<Metric>({ [self] _ in
        self.sessionSampler.shouldSample
      })
    ]
    
    traceSampleFilter.append(contentsOf: configuration.agent.spanFilters)
    logSampleFliter.append(contentsOf: configuration.agent.logFilters)
    metricSampleFilter.append(contentsOf: configuration.agent.metricFilters)
    
    let otlpConfiguration = OtlpConfiguration(
      timeout: OtlpConfiguration.DefaultTimeoutInterval,
      headers: OpenTelemetryHelper.generateExporterHeaders(configuration.agent.auth))
    let channel = OpenTelemetryHelper.getChannel(with: configuration.agent, group: group)
    
    let resources = AgentResource.get().merging(other: AgentEnvResource.get())
    let metricExporter = {
      let defaultExporter = OtlpMetricExporter(
        channel: channel, config: otlpConfiguration, logger: Logger(label: Self.logLabel))
      do {
        if let path = Self.createPersistenceFolder() {
          return try PersistenceMetricExporterDecorator(
            metricExporter: defaultExporter, storageURL: path, exportCondition: { true },
            performancePreset: configuration.instrumentation.storageConfiguration) as MetricExporter
        }
      } catch {}
      return defaultExporter as MetricExporter
    }()
    
    let traceExporter = {
      let defaultExporter = OtlpTraceExporter(
        channel: channel, config: otlpConfiguration, logger: Logger(label: Self.logLabel))
      do {
        if let path = Self.createPersistenceFolder() {
          return try PersistenceSpanExporterDecorator(
            spanExporter: OtlpTraceExporter(
              channel: channel, config: otlpConfiguration, logger: Logger(label: Self.logLabel)),
            storageURL: path, exportCondition: { true },
            performancePreset: configuration.instrumentation.storageConfiguration) as SpanExporter
        }
      } catch {}
      return defaultExporter as SpanExporter
      
    }()
    let logExporter = {
      let defaultExporter = OtlpLogExporter(
        channel: channel, config: otlpConfiguration, logger: Logger(label: Self.logLabel))
      do {
        if let path = Self.createPersistenceFolder() {
          return try PersistenceLogExporterDecorator(
            logRecordExporter: OtlpLogExporter(
              channel: channel, config: otlpConfiguration, logger: Logger(label: Self.logLabel)),
            storageURL: path, exportCondition: { true },
            performancePreset: configuration.instrumentation.storageConfiguration) as LogRecordExporter
        }
      } catch {}
      return defaultExporter as LogRecordExporter
    }()
    
    // initialize meter provider
    
    OpenTelemetry.registerMeterProvider(
      meterProvider: MeterProviderBuilder()
        .with(processor: ElasticMetricProcessor(metricSampleFilter))
        .with(resource: resources)
        .with(exporter: metricExporter)
        .build())
    
    // initialize trace provider
    OpenTelemetry.registerTracerProvider(
      tracerProvider: TracerProviderBuilder()
        .add(
          spanProcessor: ElasticSpanProcessor(
            spanExporter: traceExporter, traceSampleFilter)
        )
        .with(sampler: sessionSampler as Sampler)
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
            logSampleFliter)
        ])
        .build())
  }
  
  
  func initializeWithHttp(_ configuration: AgentConfigManager) {
    guard let  endpoint =  OpenTelemetryHelper.getURL(with: configuration.agent) else {
      os_log("Failed to start Elastic agent: invalid collector url.")
      return
    }
    
    var traceSampleFilter: [SignalFilter<ReadableSpan>] = [
      SignalFilter<ReadableSpan>({ [self] _ in
        self.sessionSampler.shouldSample
      })
    ]
    
    var logSampleFliter: [SignalFilter<ReadableLogRecord>] = [
      SignalFilter<ReadableLogRecord>({ [self] _ in
        self.sessionSampler.shouldSample
      })
    ]
    
    var metricSampleFilter: [SignalFilter<Metric>] = [
      SignalFilter<Metric>({ [self] _ in
        self.sessionSampler.shouldSample
      })
    ]
    
    traceSampleFilter.append(contentsOf: configuration.agent.spanFilters)
    logSampleFliter.append(contentsOf: configuration.agent.logFilters)
    metricSampleFilter.append(contentsOf: configuration.agent.metricFilters)
    
    let otlpConfiguration = OtlpConfiguration(
      timeout: OtlpConfiguration.DefaultTimeoutInterval,
      headers: OpenTelemetryHelper.generateExporterHeaders(configuration.agent.auth))
    
    let resources = AgentResource.get().merging(other: AgentEnvResource.get())
    let metricExporter = {
      let defaultExporter = OtlpHttpMetricExporter(endpoint: endpoint, config: otlpConfiguration, useSession: URLSession.shared)
      do {
        if let path = Self.createPersistenceFolder() {
          return try PersistenceMetricExporterDecorator(
            metricExporter: defaultExporter, storageURL: path, exportCondition: { true },
            performancePreset: configuration.instrumentation.storageConfiguration) as MetricExporter
        }
      } catch {}
      return defaultExporter as MetricExporter
    }()
    
    let traceExporter = {
      let defaultExporter = OtlpHttpTraceExporter(endpoint: endpoint, config:otlpConfiguration, useSession: URLSession.shared)
      do {
        if let path = Self.createPersistenceFolder() {
          return try PersistenceSpanExporterDecorator(
            spanExporter: defaultExporter,
            storageURL: path, exportCondition: { true },
            performancePreset: configuration.instrumentation.storageConfiguration) as SpanExporter
        }
      } catch {}
      return defaultExporter as SpanExporter
    }()
    
    let logExporter = {
      let defaultExporter = OtlpHttpLogExporter(endpoint: endpoint, config: otlpConfiguration,useSession: URLSession.shared)
      do {
        if let path = Self.createPersistenceFolder() {
          return try PersistenceLogExporterDecorator(
            logRecordExporter: defaultExporter,
            storageURL: path, exportCondition: { true },
            performancePreset: configuration.instrumentation.storageConfiguration)
          as LogRecordExporter
        }
      } catch {}
      return defaultExporter as LogRecordExporter
    }()
    
    OpenTelemetry.registerMeterProvider(
      meterProvider: MeterProviderBuilder()
        .with(processor: ElasticMetricProcessor(metricSampleFilter))
        .with(resource: resources)
        .with(exporter: metricExporter)
        .build())
    
    // initialize trace provider
    OpenTelemetry.registerTracerProvider(
      tracerProvider: TracerProviderBuilder()
        .add(
          spanProcessor: ElasticSpanProcessor(
            spanExporter: traceExporter, traceSampleFilter)
        )
        .with(sampler: sessionSampler as Sampler)
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
            logSampleFliter)
        ])
        .build())
  }
}
