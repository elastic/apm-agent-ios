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
import Logging
import OpenTelemetrySdk

struct URLTarget: Hashable {
  let scheme: String
  let host: String
  let port: Int?
  let path: String

  init?(_ url: URL) {
    guard
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let scheme = components.scheme?.lowercased(),
      let host = components.host?.lowercased()
    else {
      return nil
    }

    self.scheme = scheme
    self.host = host
    port = components.port ?? Self.defaultPort(for: scheme)
    path = Self.normalizedPath(components.path)
  }

  private static func defaultPort(for scheme: String) -> Int? {
    switch scheme {
    case "http":
      return 80
    case "https":
      return 443
    default:
      return nil
    }
  }

  private static func normalizedPath(_ path: String) -> String {
    var normalized = path.isEmpty ? "/" : path
    while normalized.count > 1, normalized.hasSuffix("/") {
      normalized.removeLast()
    }
    return normalized
  }
}

final class SDKEndpointRegistry {
  private let lock = NSLock()
  private var targets = Set<URLTarget>()

  func register(_ url: URL) {
    guard let target = URLTarget(url) else {
      return
    }
    lock.lock()
    targets.insert(target)
    lock.unlock()
  }

  func contains(_ url: URL) -> Bool {
    guard let target = URLTarget(url) else {
      return false
    }
    lock.lock()
    defer { lock.unlock() }
    return targets.contains(target)
  }

  var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return targets.count
  }
}

class AgentConfigManager {
  public let agent: AgentConfiguration
  public let central: CentralConfig
  public let instrumentation: InstrumentationConfiguration
  let centralConfigManager: CentralConfigManager
  private let endpointRegistry: SDKEndpointRegistry

  init(
    resource: Resource,
    config: AgentConfiguration,
    instrumentationConfig: InstrumentationConfiguration,
    endpointRegistry: SDKEndpointRegistry = SDKEndpointRegistry(),
    logger: Logging.Logger = Logging.Logger(label: "co.elastic.centralConfigFetcher") { _ in
      SwiftLogNoOpLogHandler()
    }
  ) {
    agent = config
    instrumentation = instrumentationConfig
    central = CentralConfig()
    self.endpointRegistry = endpointRegistry

    if config.enableOpAMP {
      centralConfigManager = OpampCentralConfigManager(
        resource: resource,
        agent: config,
        instrumentationConfig: instrumentationConfig,
        endpointRegistry: endpointRegistry,
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

  func register(_ url: URL) {
    endpointRegistry.register(url)
  }

  func isRegistered(_ url: URL) -> Bool {
    endpointRegistry.contains(url)
  }

  var registeredEndpointCount: Int {
    endpointRegistry.count
  }
}
