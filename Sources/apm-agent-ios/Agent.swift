import Foundation
import Logging
import NIO
import OpenTelemetryApi
import OpenTelemetrySdk
import os.log

public class Agent {
    
    public static func start(with configuaration: AgentConfiguration) {
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
    }

    deinit {
        try! group.syncShutdownGracefully()
        
    }
}
