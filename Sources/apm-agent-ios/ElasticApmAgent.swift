import CrashReporter
import Foundation
import NIO
import OpenTelemetryApi
import OpenTelemetrySdk
import os.log
import Kronos

public class ElasticApmAgent {
 public static let name = "apm-agent-ios"

  public static func start(
    with configuration: AgentConfiguration,
    _ instrumentationConfiguration: InstrumentationConfiguration = InstrumentationConfiguration()
  ) {
    if !configuration.enableAgent {
      os_log("Elastic APM Agent has been disabled.")
      return
    }

      Kronos.Clock.sync()
    instance = ElasticApmAgent(
      configuration: configuration, instrumentationConfiguration: instrumentationConfiguration)
  }

  public static func start() {
    ElasticApmAgent.start(with: AgentConfiguration())
  }

  public class func shared() -> ElasticApmAgent? {
    instance
  }

  private static var instance: ElasticApmAgent?

  let group: EventLoopGroup

  let instrumentation: InstrumentationWrapper

  let crashManager: CrashManager?

  let agentConfigManager: AgentConfigManager

  let openTelemetry: OpenTelemetryInitializer

  let sessionSampler: SessionSampler

  let crashConfig = CrashManagerConfiguration()

  private init(
    configuration: AgentConfiguration, instrumentationConfiguration: InstrumentationConfiguration
  ) {
    crashConfig.sessionId = SessionManager.instance.session(false)
    crashConfig.networkStatus = NetworkStatusManager().lastStatus
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
      crashManager?.initializeCrashReporter(configuration: crashConfig)
    }
  }

  deinit {
    // swiftlint:disable:next force_try
    try! group.syncShutdownGracefully()

  }
}
