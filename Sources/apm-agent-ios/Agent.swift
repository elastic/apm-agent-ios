import Foundation
import NIO
import OpenTelemetryApi
import OpenTelemetrySdk
import CrashReporter
import os.log
import TrueTime

public class Agent {
    
    
    
    public static func start(with configuration: AgentConfiguration, _ instrumentationConfiguration: InstrumentationConfiguration = InstrumentationConfiguration()) {
        if !configuration.enableAgent {
            os_log("Elastic APM Agent has been disabled.")
            return
        }
        
        TrueTimeClient.sharedInstance.start()
        instance = Agent(configuration: configuration, instrumentationConfiguration: instrumentationConfiguration)
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
    
    let instrumentation : InstrumentationWrapper
    
    let instrumentationConfiguration : InstrumentationConfiguration
    
    let crashManager : CrashManager?

    private init(configuration: AgentConfiguration, instrumentationConfiguration : InstrumentationConfiguration) {
        self.configuration = configuration
        self.instrumentationConfiguration = instrumentationConfiguration
        instrumentation = InstrumentationWrapper(config: instrumentationConfiguration)
        _ = OpenTelemetrySDK.instance // initialize sdk, or else it will over write our providers

        group = OpenTelemetryInitializer.initialize(configuration)

        if instrumentationConfiguration.enableCrashReporting {
            crashManager = CrashManager(resource:AgentResource.get().merging(other: AgentEnvResource.resource),
                                        group: group,
                                        agentConfiguration: configuration)
        } else {
            crashManager = nil
        }
        os_log("Initializing Elastic APM Agent.")
    }

    private func initialize() {
        if instrumentationConfiguration.enableCrashReporting {
            crashManager?.initializeCrashReporter()
        }
        instrumentation.initalize()
    }



    deinit {
        try! group.syncShutdownGracefully()
        
    }
}
