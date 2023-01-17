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
import OpenTelemetryApi
import OpenTelemetrySdk
import OpenTelemetryProtocolExporter
import CrashReporter
import Logging
import os.log
import GRPC
import NIO


struct CrashManager {
    static let CRASH_MANAGER_VERSION = "0.0.1"
    static let LOG_LABEL = "Elastic-OTLP-Exporter"
    static let lastResourceDefaultsKey : String = "elastic.last.resource"
    let lastResource : Resource
    let group : EventLoopGroup
    let loggerProvider : LoggerProvider
    init(resource: Resource, group: EventLoopGroup, agentConfiguration: AgentConfiguration) {
        self.group = group
        // if something went wrong with the lastResource in the user defaults, fallback of the current resource data.
        var tempResource = resource
        
        let otlpConfiguration = OtlpConfiguration(timeout: OtlpConfiguration.DefaultTimeoutInterval, headers: OpenTelemetryHelper.generateExporterHeaders(agentConfiguration.auth))

        
        if let lastResourceJson  = UserDefaults.standard.data(forKey: Self.lastResourceDefaultsKey) {
            do {
                let decoder = JSONDecoder()
                tempResource = try decoder.decode(Resource.self, from: lastResourceJson)
            } catch {
                os_log("[Elastic][CrashManager] initialization: unable to load last Resource from user defaults.")
            }
        }
        lastResource = tempResource
        loggerProvider = LoggerProviderBuilder()
            .with(resource: lastResource)
            .with(processors: [SimpleLogRecordProcessor(logRecordExporter: OtlpLogExporter(channel: OpenTelemetryHelper.getChannel(with: agentConfiguration, group: group),
                                                                                           config: otlpConfiguration,
                                                                                           logger: Logger(label:Self.LOG_LABEL), envVarHeaders: OpenTelemetryHelper.generateExporterHeaders(agentConfiguration.auth)))])
            .build()
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(resource)
            UserDefaults.standard.set(data, forKey:Self.lastResourceDefaultsKey)
        } catch {
            os_log("[Elastic][CrashManager] initialization: unable to save current Resource from user defaults.")

        }
    }
    
    public func initializeCrashReporter() {
        // It is strongly recommended that local symbolication only be enabled for non-release builds.
        // Use [] for release versions.
        let config = PLCrashReporterConfig(signalHandlerType: .mach, symbolicationStrategy: [])
        guard let crashReporter = PLCrashReporter(configuration: config) else {
          print("Could not create an instance of PLCrashReporter")
          return
        }

        // Enable the Crash Reporter.
        do {
          try crashReporter.enableAndReturnError()
        } catch let error {
          print("Warning: Could not enable crash reporter: \(error)")
        }
        
        // Try loading the crash report.
        if crashReporter.hasPendingCrashReport() {
          do {
            let data = try crashReporter.loadPendingCrashReportDataAndReturnError()
              let lp = loggerProvider.loggerBuilder(instrumentationScopeName: "PLCrashReporter")
                  .setInstrumentationVersion(Self.CRASH_MANAGER_VERSION)
                  .setEventDomain("device")
                  .build()
                  
              
            // Retrieving crash reporter data.
            let report = try PLCrashReport(data: data)

            // We could send the report from here, but we'll just print out some debugging info instead.
            if let text = PLCrashReportTextFormatter.stringValue(for: report, with: PLCrashReportTextFormatiOS) {
              print(text)
                // notes : branching code needed for signal vs mach vs nsexception for event generation
                //
                var attributes = [
                    "exception.type": AttributeValue.string(report.signalInfo.name),
                    "exception.stacktrace": AttributeValue.string(text)
                ]
                if let code = report.signalInfo.code {
                    attributes["exception.message"] = AttributeValue.string("\(code) at \(report.signalInfo.address)")
                }
                
                lp.eventBuilder(name: "crash")
                    .setSeverity(.fatal)
                    .setObservedTimestamp(report.systemInfo.timestamp)
                    .setAttributes(attributes)
                    .emit()
                
            } else {
              print("CrashReporter: can't convert report to text")
            }
          } catch let error {
            print("CrashReporter failed to load and parse with error: \(error)")
          }
              
        }

        // Purge the report.
        crashReporter.purgePendingCrashReport()
    }
}