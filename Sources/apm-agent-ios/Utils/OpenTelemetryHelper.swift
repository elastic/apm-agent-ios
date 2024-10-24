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

    var port = "\(config.collectorPort)"
    if config.collectorPort == 80 || config.collectorPort == 443 {
      port = ""
    }

    return URL(string: "\(config.collectorTLS ? "https://" : "http://")\(config.collectorHost)\( port.isEmpty ? "" : ":\(port)")")

  }

    public static func getChannel(with config: AgentConfiguration, group: EventLoopGroup) -> ClientConnection {

        if config.collectorTLS {
             return ClientConnection.usingPlatformAppropriateTLS(for: group)
                 .connect(host: config.collectorHost, port: config.collectorPort)
         } else {
              return ClientConnection.insecure(group: group)
                 .connect(host: config.collectorHost, port: config.collectorPort)
         }

    }
}
