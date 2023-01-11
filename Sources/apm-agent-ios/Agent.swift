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
    
    let crashManager : CrashManager

    private init(configuration: AgentConfiguration) {
        self.configuration = configuration
        
        _ = OpenTelemetrySDK.instance // initialize sdk, or else it will over write our providers

        group = OpenTelemetryInitializer.initialize(configuration)

        crashManager = CrashManager(resource:AgentResource.get().merging(other: AgentEnvResource.resource),
                                    group: group,
                                    agentConfiguration: configuration)
        os_log("Initializing Elastic APM Agent.")
    }

    private func initialize() {
        crashManager.initializeCrashReporter()
        instrumentation.initalize()
    }



    deinit {
        try! group.syncShutdownGracefully()
        
    }
}
