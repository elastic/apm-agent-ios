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
import ResourceExtension



class OpenTelemetryInitializer {
    static let LOG_LABEL = "Elastic-OTLP-Exporter"
    static let AGENT_NAME = "apm-agent-ios"
    struct Headers {
        static let userAgent = "user-agent"
        static let authorization = "authorization"
        static let bearer = "bearer"
        static let api = "ApiKey"
    }

    static func initialize(_ configuration : AgentConfiguration) -> EventLoopGroup {
        let otlpConfiguration = OtlpConfiguration(timeout: OtlpConfiguration.DefaultTimeoutInterval, headers: Self.generateExporterHeaders(configuration.secretToken))
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let channel = Self.getChannel(with: configuration, group: group)
        
        let resources = AgentResource.get().merging(other: AgentEnvResource.resource)
        
        
        // initialize meter provider
        OpenTelemetry.registerMeterProvider(meterProvider: MeterProviderBuilder()
            .with(processor: MetricProcessorSdk())
            .with(resource: resources )
            .with(exporter: OtlpMetricExporter(channel: channel, config: otlpConfiguration, logger: Logger(label:Self.LOG_LABEL)))
            .build())
    

         // initialize trace provider
        OpenTelemetry.registerTracerProvider(tracerProvider: TracerProviderBuilder()
            .add(spanProcessor: BatchSpanProcessor(spanExporter: OtlpTraceExporter(channel: channel, config: otlpConfiguration, logger: Logger(label:Self.LOG_LABEL))) { spanData in
                // This is for clock skew compensation
                    let exportTimestamp = Date().timeIntervalSince1970.toNanoseconds
                    for i in spanData.indices {
                    // This is for clock skew compensation
                        let newResource = spanData[i].resource.merging(other: Resource(attributes: [ElasticAttributes.exportTimestamp.rawValue: AttributeValue.int(Int(exportTimestamp))]))
                        _ = spanData[i].settingResource(newResource)
                }
            })
            .with(resource: resources)
            .build())

        return group
    }
    
    private static func getChannel(with config: AgentConfiguration, group: EventLoopGroup) -> ClientConnection {
      
        if config.collectorTLS {
             return ClientConnection.usingPlatformAppropriateTLS(for: group)
                 .connect(host: config.collectorHost, port: config.collectorPort)
         } else {
              return ClientConnection.insecure(group: group)
                 .connect(host: config.collectorHost, port: config.collectorPort)
         }
         
    }
    
    private static func generateExporterHeaders(_ token: String?) -> [(String, String)]? {
        var headers = [(String, String)]()
        if let t = token {
            headers.append((Headers.authorization, "\(Headers.bearer) \(t)"))
        }
        headers.append((Headers.userAgent, generateExporterUserAgent()))

        return headers
    }

    private static func generateExporterUserAgent() -> String {
        var userAgent = "\(AGENT_NAME)/\(Agent.ELASTIC_SWIFT_AGENT_VERSION)"
        let appInfo = ApplicationDataSource()
        if let appName = appInfo.name {
            var appIdent = appName
            if let appVersion = appInfo.version {
                appIdent += " \(appVersion)"
            }
            userAgent += " (\(appIdent))"
        }
        return userAgent
    }
}
