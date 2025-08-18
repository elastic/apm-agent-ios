#if !os(watchOS)
import CrashReporter
import Kronos
#endif
import Foundation
import NIO
import OpenTelemetryApi
import OpenTelemetrySdk
import os.log
import Logging

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
    #if !os(watchOS)
    Kronos.Clock.sync()
    #endif

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

  #if !os(watchOS)
  let crashManager: CrashManager?
  #endif

  let crashLogExporter: LogRecordExporter

  let agentConfigManager: AgentConfigManager

  let openTelemetry: OpenTelemetryInitializer

  let sessionSampler: SessionSampler

  let crashConfig = CrashManagerConfiguration()

  private init(
    configuration: AgentConfiguration, instrumentationConfiguration: InstrumentationConfiguration
  ) {
    crashConfig.sessionId = SessionManager.instance.session(false)
    #if os(iOS) && !targetEnvironment(macCatalyst)
      crashConfig.networkStatus = NetworkStatusManager().lastStatus
    #endif // os(iOS) && !targetEnvironment(macCatalyst)

    _ = SessionManager.instance.session()  // initialize session
    agentConfigManager = AgentConfigManager(
      resource: AgentResource.get().merging(other: AgentEnvResource.get()),
 config: configuration,
      instrumentationConfig: instrumentationConfiguration,
      logger: Logging.Logger(label: "Elastic.ConfigManager")
    )

    sessionSampler = SessionSampler({
      if let rate = CentralConfig().data.sampleRate {
        return rate
      }
      return configuration.sampleRate
    })

    instrumentation = InstrumentationWrapper(config: agentConfigManager)

    group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    openTelemetry = OpenTelemetryInitializer(group: group, sessionSampler: sessionSampler)

      if agentConfigManager.agent.connectionType == .grpc {
        crashLogExporter = openTelemetry.initialize(agentConfigManager)
      } else {
        crashLogExporter = openTelemetry.initializeWithHttp(agentConfigManager)
      }

    #if !os(watchOS)
    if instrumentationConfiguration.enableCrashReporting {
      crashManager = CrashManager(
        resource: AgentResource.get().merging(other: AgentEnvResource.get()),
        logExporter: crashLogExporter)
    } else {
      crashManager = nil
    }
    #endif

    os_log("Initializing Elastic APM Agent.")

    instrumentation.initalize()

    #if !os(watchOS)
    if agentConfigManager.instrumentation.enableCrashReporting {
      crashManager?.initializeCrashReporter(configuration: crashConfig)
    }
    #endif
  }

  deinit {
    // swiftlint:disable:next force_try
    try! group.syncShutdownGracefully()

  }
}
