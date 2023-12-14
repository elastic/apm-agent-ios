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

  let sessionSampler: SessionSampler
    

  private init(
    configuration: AgentConfiguration, instrumentationConfiguration: InstrumentationConfiguration
  ) {
    let lastSessionForCrashReport = SessionManager.instance.session(false)
    _ = SessionManager.instance.session()  // initialize session
    agentConfigManager = AgentConfigManager(
      resource: AgentResource.get().merging(other: AgentEnvResource.get()), config: configuration,
      instrumentationConfig: instrumentationConfiguration)

    sessionSampler = SessionSampler({
      if let rate = CentralConfig().data.sampleRate {
        return rate
      }
      return configuration.sampleRate
    })

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

    instrumentation.initalize()
    if agentConfigManager.instrumentation.enableCrashReporting {
      crashManager?.initializeCrashReporter(lastSession: lastSessionForCrashReport)
    }
  }

  deinit {
    // swiftlint:disable:next force_try
    try! group.syncShutdownGracefully()

  }
}
