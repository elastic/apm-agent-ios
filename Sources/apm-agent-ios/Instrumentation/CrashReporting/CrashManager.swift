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

import CrashReporter
import Foundation
import Logging
import OpenTelemetryApi
import OpenTelemetrySdk

import os.log

struct CrashManager {
  static let crashEventName: String = "crash"
  static let crashManagerVersion = "0.0.3"
  static let lastResourceDefaultsKey: String = "elastic.last.resource"
  static let instrumentationName = "PLCrashReporter"
  let lastResource: Resource
  let loggerProvider: LoggerProvider
  private let logger = OSLog(subsystem: "co.elastic.crash-reporter", category: "instrumentation")
  init(resource: Resource, logExporter: LogRecordExporter) {
    // if something went wrong with the lastResource in the user defaults, fallback of the current resource data.
    var tempResource = resource

    if let lastResourceJson = UserDefaults.standard.data(forKey: Self.lastResourceDefaultsKey) {
      do {
        let decoder = JSONDecoder()
        tempResource = try decoder.decode(Resource.self, from: lastResourceJson)
      } catch {
        os_log("initialization: unable to load last Resource from user defaults.",
               log: logger,
               type: .error)
      }
    }
    lastResource = tempResource
      loggerProvider = LoggerProviderBuilder()
        .with(resource: lastResource)
        .with(processors: [
          BatchLogRecordProcessor(
            logRecordExporter: logExporter
          )
        ])
        .build()

    do {
      let encoder = JSONEncoder()
      let data = try encoder.encode(resource)
      UserDefaults.standard.set(data, forKey: Self.lastResourceDefaultsKey)
    } catch {
      os_log("initialization: unable to save current Resource from user defaults.", log: logger,  type: .error)

    }
  }


  public func initializeCrashReporter(configuration: CrashManagerConfiguration) {
    // It is strongly recommended that local symbolication only be enabled for non-release builds.
    // Use [] for release versions.
    let config = PLCrashReporterConfig(signalHandlerType: getSignalHandler(), symbolicationStrategy: [])
    guard let crashReporter = PLCrashReporter(configuration: config) else {
      os_log("Could not create an instance of PLCrashReporter", log: logger, type: .error)
      return
    }

    // Enable the Crash Reporter.
    do {
      if !isDebuggerAttached() {
        try crashReporter.enableAndReturnError()
      }
    } catch let error {
      os_log("Warning: Could not enable crash reporter: %@",
             log: logger,
             type: .error,
             error.localizedDescription)
    }

    // Try loading the crash report.
    if crashReporter.hasPendingCrashReport() {
      do {
        let data = try crashReporter.loadPendingCrashReportDataAndReturnError()
        let logger = loggerProvider.loggerBuilder(instrumentationScopeName: Self.instrumentationName)
          .setInstrumentationVersion(Self.crashManagerVersion)
          .setEventDomain(SemanticAttributes.EventDomainValues.device.description)
          .build()

        // Retrieving crash reporter data.
        let report = try PLCrashReport(data: data)

        // We could send the report from here, but we'll just print out some debugging info instead.
        if let text = PLCrashReportTextFormatter.stringValue(
          for: report, with: PLCrashReportTextFormatiOS) {
          os_log("%@", log:self.logger, type: .debug, text)
          // notes : branching code needed for signal vs mach vs nsexception for event generation
          //
          var attributes = [
            SemanticAttributes.exceptionType.rawValue: AttributeValue.string(report.signalInfo.name),
            SemanticAttributes.exceptionStacktrace.rawValue: AttributeValue.string(text)
          ]

          if let lastSessionId = configuration.sessionId {
            attributes[ElasticAttributes.sessionId.rawValue] = AttributeValue.string(lastSessionId)
          }

          if let lastNetworkStatus = configuration.networkStatus {
            attributes[SemanticAttributes.networkConnectionType.rawValue] = AttributeValue.string(lastNetworkStatus)
          }

          if let code = report.signalInfo.code {
              attributes[SemanticAttributes.exceptionMessage.rawValue] = AttributeValue.string(
              "\(code) at \(report.signalInfo.address)")
          }

          logger.eventBuilder(name: Self.crashEventName)
            .setSeverity(.fatal)
            .setObservedTimestamp(report.systemInfo.timestamp)
            .setAttributes(attributes)
            .emit()

        } else {
          os_log("CrashReporter: can't convert report to text",log: self.logger, type: .error)
        }
      } catch let error {
        os_log("CrashReporter failed to load and parse with error: %@",
               log: logger,
               type: .error,
               error.localizedDescription)
      }

    }

    // Purge the report.
    crashReporter.purgePendingCrashReport()
  }

  
  private func getSignalHandler() -> PLCrashReporterSignalHandlerType {
    #if os(tvOS)
      return .BSD
    #else
      return .mach
    #endif
  }
  
  private func isDebuggerAttached() -> Bool {
    var info = kinfo_proc()
    let infoSize = UnsafeMutablePointer<Int>.allocate(capacity: 1)
    infoSize[0] = MemoryLayout<kinfo_proc>.size
    let name = UnsafeMutablePointer<Int32>.allocate(capacity: 4)

    name[0] = CTL_KERN
    name[1] = KERN_PROC
    name[2] = KERN_PROC_PID
    name[3] = getpid()

    if sysctl(name, 4, &info, infoSize, nil, 0) == -1 {
      os_log("sysctl() failed: %@",
             log: logger,
             type:.error,
             String(describing: strerror(errno)))
      return false
    }

    if (info.kp_proc.p_flag & P_TRACED) != 0 {
      return true
    }

    return false
  }
}
