import CrashReporter
import Foundation
import NIO
import OpenTelemetryApi
import OpenTelemetrySdk
import TrueTime
import os.log

public class Agent {

  public static func start(
    with configuration: AgentConfiguration,
    _ instrumentationConfiguration: InstrumentationConfiguration = InstrumentationConfiguration()
  ) {
    if !configuration.enableAgent {
      os_log("Elastic APM Agent has been disabled.")
      return
    }

    TrueTimeClient.sharedInstance.start()
    instance = Agent(
      configuration: configuration, instrumentationConfiguration: instrumentationConfiguration)
    instance?.initialize()
  }

  public static func start() {
    Agent.start(with: AgentConfiguration())
  }

  public class func shared() -> Agent? {
    instance
  }

  private static var instance: Agent?

  let group: EventLoopGroup

  let instrumentation: InstrumentationWrapper

  let crashManager: CrashManager?

  let agentConfigManager: AgentConfigManager

  let openTelemetry: OpenTelemetryInitializer

  let sessionSampler = SessionSampler()

  private init(
    configuration: AgentConfiguration, instrumentationConfiguration: InstrumentationConfiguration
  ) {
    agentConfigManager = AgentConfigManager(
      resource: AgentResource.get().merging(other: AgentEnvResource.get()), config: configuration,
      instrumentationConfig: instrumentationConfiguration)

    instrumentation = InstrumentationWrapper(config: agentConfigManager)

    group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    openTelemetry = OpenTelemetryInitializer(group: group, sessionSampler: sessionSampler)

    openTelemetry.initialize(agentConfigManager)

    if instrumentationConfiguration.enableCrashReporting {
      crashManager = CrashManager(
        resource: AgentResource.get().merging(other: AgentEnvResource.get()),
        group: group,
        agentConfiguration: agentConfigManager.agent)
    } else {
      crashManager = nil
    }
    os_log("Initializing Elastic APM Agent.")
  }

  private func initialize() {
    if agentConfigManager.instrumentation.enableCrashReporting {
      crashManager?.initializeCrashReporter()
    }
    instrumentation.initalize()
  }

  deinit {
    try! group.syncShutdownGracefully()

  }
}
