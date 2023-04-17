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
import OpenTelemetryApi
import OpenTelemetrySdk
import OpenTelemetryProtocolExporter
import GRPC
import NIO
import Logging




class OpenTelemetryInitializer {
    static let LOG_LABEL = "Elastic-OTLP-Exporter"

    static func initialize(_ configuration : AgentConfigManager) -> EventLoopGroup {
        let otlpConfiguration = OtlpConfiguration(timeout: OtlpConfiguration.DefaultTimeoutInterval, headers: OpenTelemetryHelper.generateExporterHeaders(configuration.agent.auth))
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let channel = OpenTelemetryHelper.getChannel(with: configuration.agent, group: group)
        
        let resources = AgentResource.get().merging(other: AgentEnvResource.resource)
        
                
        // initialize meter provider
        OpenTelemetry.registerMeterProvider(meterProvider: MeterProviderBuilder()
            .with(processor: ElasticMetricProcessor())
            .with(resource: resources )
            .with(exporter: OtlpMetricExporter(channel: channel, config: otlpConfiguration, logger: Logger(label:Self.LOG_LABEL)))
            .build())
    
         // initialize trace provider
        OpenTelemetry.registerTracerProvider(tracerProvider: TracerProviderBuilder()
            .add(spanProcessor: ElasticSpanProcessor(spanExporter: OtlpTraceExporter(channel: channel, config: otlpConfiguration, logger: Logger(label:Self.LOG_LABEL))))
            .with(resource: resources)
            .with(clock: NTPClock())
            .build())

        OpenTelemetry.registerLoggerProvider(loggerProvider: LoggerProviderBuilder()
            .with(clock: NTPClock())
            .with(resource: resources)
            .with(processors: [ElasticLogRecordProcessor(logRecordExporter: OtlpLogExporter(channel: channel, config: otlpConfiguration, logger: Logger(label: Self.LOG_LABEL)))])
            .build())
        
        return group
    }
    
    
    
   
}
