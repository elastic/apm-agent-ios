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

    static func initialize(_ configuration : AgentConfiguration) -> EventLoopGroup {
        let otlpConfiguration = OtlpConfiguration(timeout: OtlpConfiguration.DefaultTimeoutInterval, headers: OpenTelemetryHelper.generateExporterHeaders(configuration.auth))
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let channel = OpenTelemetryHelper.getChannel(with: configuration, group: group)
        
        let resources = AgentResource.get().merging(other: AgentEnvResource.resource)
        
        
        // initialize meter provider
        OpenTelemetry.registerMeterProvider(meterProvider: MeterProviderBuilder()
            .with(processor: MetricProcessorSdk())
            .with(resource: resources )
            .with(exporter: OtlpMetricExporter(channel: channel, config: otlpConfiguration, logger: Logger(label:Self.LOG_LABEL)))
            .build())
    

         // initialize trace provider
        OpenTelemetry.registerTracerProvider(tracerProvider: TracerProviderBuilder()
            .add(spanProcessor: BatchSpanProcessor(spanExporter: OtlpTraceExporter(channel: channel, config: otlpConfiguration, logger: Logger(label:Self.LOG_LABEL))))
            .with(resource: resources)
            .with(clock: NTPClock())
            .build())

        return group
    }
    
    
    
   
}
