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

class AgentConfigManager {
  public let agent: AgentConfiguration
  public let central: CentralConfig
  public let instrumentation: InstrumentationConfiguration
  let centralConfigManager: CentralConfigManager
  
  init(resource: Resource,
       config: AgentConfiguration,
       instrumentationConfig: InstrumentationConfiguration,
       logger: Logging.Logger = Logging.Logger(label: "co.elastic.centralConfigFetcher") { _ in
    SwiftLogNoOpLogHandler()
  }) {
    agent = config
    instrumentation = instrumentationConfig
    central = CentralConfig()

    if (config.enableOpAMP) {
      centralConfigManager = OpampCentralConfigManager(
        resource: resource,
        agent:config,
        instrumentationConfig: instrumentationConfig,
        logger: logger
      )
    } else {
      centralConfigManager = ElasticAgentConfigManager(
        resource: resource,
        config: config,
        instrumentationConfig: instrumentationConfig,
        logger: logger
      )
    }
  }
}

