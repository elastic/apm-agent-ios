// Copyright © 2024 Elasticsearch BV
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
//import os.log

struct HangDiagnosticManager {
    static let eventName: String = "hangDiagnostic"
    static let exceptionType: String = "HANG"
    static let managerVersion = "0.0.1" //TBD
    static let logLabel = "Elastic-OTLP-Exporter"
    static let lastResourceDefaultsKey: String = "elastic.last.resource"
    static let instrumentationName = "PLCrashReporter" //TBD: rename
    let group: EventLoopGroup
    let loggerProvider: LoggerProvider

    init(resource: Resource, group: EventLoopGroup, agentConfiguration: AgentConfiguration) {
        self.group = group

        let otlpConfiguration = OtlpConfiguration(
            timeout: OtlpConfiguration.DefaultTimeoutInterval,
            headers: OpenTelemetryHelper.generateExporterHeaders(agentConfiguration.auth))

        loggerProvider = LoggerProviderBuilder()
            .with(resource: resource)
            .with(processors: [
                BatchLogRecordProcessor(logRecordExporter: OtlpLogExporter(
                    channel: OpenTelemetryHelper.getChannel(with: agentConfiguration, group: group),
                    config: otlpConfiguration,
                    logger: Logger(label: Self.logLabel),
                    envVarHeaders: OpenTelemetryHelper.generateExporterHeaders(agentConfiguration.auth)))
            ])
            .build()
    }

    public func initializeCrashReporter(configuration: CrashManagerConfiguration) {
        let logger = loggerProvider.loggerBuilder(instrumentationScopeName: Self.instrumentationName)
            .setInstrumentationVersion(Self.managerVersion)
            .setEventDomain(SemanticAttributes.EventDomainValues.device.description)
            .build()

        var attributes = [
            SemanticAttributes.exceptionType.rawValue: AttributeValue.string(Self.exceptionType),
            SemanticAttributes.exceptionStacktrace.rawValue: AttributeValue.string("") //TBD: should be stackTrace of hang diagnostic
        ]

        //        if let lastSessionId = configuration.sessionId {
        //            attributes[ElasticAttributes.sessionId.rawValue] = AttributeValue.string(lastSessionId)
        //        }
        //
        //        if let lastNetworkStatus = configuration.networkStatus {
        //            attributes[SemanticAttributes.networkConnectionType.rawValue] = AttributeValue.string(lastNetworkStatus)
        //        }
        //
        //        if let code = report.signalInfo.code {
        //            attributes[SemanticAttributes.exceptionMessage.rawValue] = AttributeValue.string(
        //                "\(code) at \(report.signalInfo.address)")

        logger.eventBuilder(name: Self.eventName)
            .setSeverity(.fatal)
            .setObservedTimestamp(Date()) //TBD get report date
            .setAttributes(attributes)
            .emit()
    }
}
