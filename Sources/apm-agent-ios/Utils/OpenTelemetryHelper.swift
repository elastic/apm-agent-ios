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
import OpenTelemetryApi
import OpenTelemetrySdk
import ResourceExtension
import GRPC
import NIO

struct GrpcChannelTarget: Equatable {
  let host: String
  let port: Int
  let useTLS: Bool

  init(host: String, port: Int, useTLS: Bool) {
    self.host = host
    self.port = port
    self.useTLS = useTLS
  }

  init?(endpoint: URL) {
    guard
      let host = endpoint.host,
      let scheme = endpoint.scheme?.lowercased(),
      scheme == "http" || scheme == "https",
      endpoint.port.map({ (1 ... 65_535).contains($0) }) ?? true
    else {
      return nil
    }

    self.host = host
    useTLS = scheme == "https"
    port = endpoint.port ?? (useTLS ? 443 : 80)
  }
}

public class OpenTelemetryHelper {
    struct Headers {
        static let userAgent = "User-Agent"
        static let authorization = "Authorization"
    }

    public static func generateExporterHeaders(_ auth: String?) -> [(String, String)]? {
        var headers = [(String, String)]()
        if let auth = auth {
            headers.append((Headers.authorization, "\(auth)"))
        }
        headers.append((Headers.userAgent, generateExporterUserAgent()))

        return headers
    }

    public static func generateExporterUserAgent() -> String {
        var userAgent = "\(ElasticApmAgent.name)/\(ElasticApmAgent.elasticSwiftAgentVersion)"
        let appInfo = ApplicationDataSource()
        if let appName = appInfo.name {
            var appIdent = appName
            if let appVersion = appInfo.version {
                appIdent += " \(appVersion)"
            }
            userAgent += " (\(appIdent))"
        }
        return userAgent
    }

  public static func getURL(with config: AgentConfiguration) -> URL? {
    config.resolvedExportUrl ?? config.resolveExportEndpoint().url
  }

  static func channelTarget(with config: AgentConfiguration) -> GrpcChannelTarget? {
    guard let endpoint = getURL(with: config) else {
      return nil
    }
    return GrpcChannelTarget(endpoint: endpoint)
  }

  static func makeChannel(
    target: GrpcChannelTarget,
    group: EventLoopGroup
  ) -> ClientConnection {
    if target.useTLS {
      return ClientConnection.usingPlatformAppropriateTLS(for: group)
        .connect(host: target.host, port: target.port)
    }
    return ClientConnection.insecure(group: group)
      .connect(host: target.host, port: target.port)
  }

  @available(
    *,
    deprecated,
    message: "Start telemetry with ElasticApmAgent.start(with:) instead."
  )
  public static func getChannel(
    with config: AgentConfiguration,
    group: EventLoopGroup
  ) -> ClientConnection {
    guard let target = channelTarget(with: config) else {
      preconditionFailure(AgentConfiguration.exportEndpointValidationMessage)
    }

    return makeChannel(target: target, group: group)
  }
}
