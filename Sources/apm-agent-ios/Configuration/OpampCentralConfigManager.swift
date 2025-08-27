//
//  Copyright © 2025  Elasticsearch BV
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
import OpenTelemetrySdk
import Logging

public class OpampCentralConfigManager: CentralConfigManager, OpampClientCallback {
  public typealias Client = OpampClientImpl
  let client: Client
  let logger: Logger

  deinit {
    client.stop()
  }

  init(
    resource: Resource,
    agent: AgentConfiguration,
    instrumentationConfig: InstrumentationConfiguration,
    logger: Logging.Logger = Logging.Logger(label: "co.elastic.centralConfig.opamp") { _ in
      SwiftLogNoOpLogHandler()
    }
  ) {
    self.logger = logger

    let builder = OpampClient.builder()

    switch resource.attributes[ResourceAttributes.deploymentEnvironment.rawValue] {
    case let .string(value):
      builder.setServiceEnvironment(value)
    default:
      break
    }

    switch resource.attributes[ResourceAttributes.serviceName.rawValue] {
    case let .string(value):
      builder.setServiceName(value)
    default:
      break
    }

    switch resource.attributes[ResourceAttributes.serviceVersion.rawValue] {
    case let .string(value):
      builder.setServiceVersion(value)
    default:
      break
    }

    switch resource.attributes[ResourceAttributes.deviceId.rawValue] {
    case let .string(value):
      if let uuid = UUID(uuidString: value) {
        builder.setInstsanceUid(uuid)
      }
    default:
      break
    }

    builder.enableRemoteConfig()
    builder.enableEffectiveConfigReporting()

    let httpClient = {

      if let url = agent.managementUrlComponents().url {
        return OpampHttpSender(
          url: url,
          headers: OpenTelemetryHelper.generateExporterHeaders(agent.auth)
        )
      } else
      {
        logger.error("Unable to parse manament url; using default: http://localhost:4320/v1/opamp")
        return OpampHttpSender(url: URL(string: "http://localhost:4320/v1/opamp")!)
      }
    }()

    let requestService = OpampHttpRequestService(
      httpClient: httpClient
    )

    self.client = builder.build(requestService: requestService)
    super.init()

    self.client.start(self)
    }

  // Opamp Callbacks
  public func onConnect(client: OpampClientImpl) {
    logger.info("OpAPM onConnect success.")
  }

  public func onConnectFailed(
    client: OpampClientImpl,
    error: any Error,
    retryAfter: TimeInterval
  ) {
    logger.error("OpAMP connection failed: \"\(error.localizedDescription)\"")

  }

  public func onErrorResponse(
    client: OpampClientImpl,
    error: any Error,
    retryAfter: TimeInterval
  ) {
    logger.error("OpAMP response error recieved: \"\(error.localizedDescription)\"")

  }

  public func onMessage(client: OpampClientImpl, message: OpampMessage) {
    if message.remoteConfig.hasConfig,   let elasticConfigMap = message.remoteConfig.config.configMap["elastic"]  {
      CentralConfig().config = String(data: elasticConfigMap.body, encoding: .utf8)
    }
  }


}
