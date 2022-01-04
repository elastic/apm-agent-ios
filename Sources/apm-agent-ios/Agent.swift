import Foundation
import NIO
import OpenTelemetryApi
import OpenTelemetrySdk
import CrashReporter
import os.log
import TrueTime

public class Agent {
    
    public static func start(with configuaration: AgentConfiguration) {
        TrueTimeClient.sharedInstance.start()
        instance = Agent(configuration: configuaration)
        instance?.initialize()
    }

    public static func start() {
        Agent.start(with: AgentConfiguration(noop: ""))
    }

    public class func shared() -> Agent? {
        instance
    }
    
    private static var instance: Agent?

    var configuration: AgentConfiguration
    
    let group : EventLoopGroup
    
    let instrumentation = InstrumentationWrapper()

    private init(configuration: AgentConfiguration) {
        self.configuration = configuration
        
        _ = OpenTelemetrySDK.instance // initialize sdk, or else it will over write our providers

        group = OpenTelemetryInitializer.initialize(configuration)

        os_log("Initializing Elastic APM Agent.")
    }

    private func initialize() {
        instrumentation.initalize()
        initializeCrashReporter()
    }

    private func initializeCrashReporter() {
        // It is strongly recommended that local symbolication only be enabled for non-release builds.
        // Use [] for release versions.
        let config = PLCrashReporterConfig(signalHandlerType: .mach, symbolicationStrategy: [])
        guard let crashReporter = PLCrashReporter(configuration: config) else {
          print("Could not create an instance of PLCrashReporter")
          return
        }

        // Enable the Crash Reporter.
        do {
//          try crashReporter.enableAndReturnError()
        } catch let error {
          print("Warning: Could not enable crash reporter: \(error)")
        }
        
        // Try loading the crash report.
        if crashReporter.hasPendingCrashReport() {
          do {
            let data = try crashReporter.loadPendingCrashReportDataAndReturnError()
              let tp = OpenTelemetrySDK.instance.tracerProvider.get(instrumentationName: "CrashReport", instrumentationVersion: "0.0.1")
            // Retrieving crash reporter data.
            let report = try PLCrashReport(data: data)
              let sp = tp.spanBuilder(spanName: "crash").startSpan()

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
                sp.addEvent(name: "exception", attributes: attributes)
                sp.end()
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

    deinit {
        try! group.syncShutdownGracefully()
        
    }
}
