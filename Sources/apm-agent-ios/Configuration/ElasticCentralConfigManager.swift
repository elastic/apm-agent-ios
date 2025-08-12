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

import Foundation
import OpenTelemetrySdk
import Logging

enum CentralConfigResponse: Int {
  case okay = 200
  case notModified = 304
  case forbidden = 403
  case notFound = 40
  case unavailable = 503
}

class ElasticAgentConfigManager: CentralConfigManager {
  public let agent: AgentConfiguration
  public let central: CentralConfig
  public let instrumentation: InstrumentationConfiguration

  let serviceEnvironment: String
  let serviceName: String
  let logger: Logger
  let resource: Resource

  var fetcher: CentralConfigFetcher?

  init(resource: Resource,
       config: AgentConfiguration,
       instrumentationConfig: InstrumentationConfiguration,
       logger: Logging.Logger = Logging.Logger(label: "co.elastic.centralConfigFetcher") { _ in
    SwiftLogNoOpLogHandler()
  }) {
    self.resource = resource
    self.agent = config
    self.instrumentation = instrumentationConfig
    self.logger = logger
    switch resource.attributes[ResourceAttributes.deploymentEnvironment.rawValue] {
    case let .string(value):
      serviceEnvironment = value
    default:
      serviceEnvironment = ""
    }

    switch resource.attributes[ResourceAttributes.serviceName.rawValue] {
    case let .string(value):
      serviceName = value
    default:
      serviceName = ""
    }

    self.central = CentralConfig()

    if agent.enableRemoteManagement {
      fetcher = CentralConfigFetcher(serviceName: serviceName,
                                     environment: serviceEnvironment,
                                     agentConfig: config, { data in
        self.central.config = String(data: data, encoding: .utf8)
      })
    }
  }
}
