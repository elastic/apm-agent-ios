// Copyright © 2022 Elasticsearch BV
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

public class AgentConfigBuilder {
    var url : URL?
    var auth : String?
    static let bearer = "bearer"
    static let api = "ApiKey"
    
    public init() {}
    
    public func withServerUrl(_ url: URL) -> Self {
        self.url = url
        return self
    }
    
    public func withSecretToken(_ token: String) -> Self {
        self.auth = "\(Self.bearer) \(token)"
        return self
    }
    
    public func withApiKey(_ key: String) -> Self {
        self.auth = "\(Self.api) \(key)"
        return self
    }
    
    public func build() -> AgentConfiguration {
        
        var config = AgentConfiguration(noop: "")
        if let url = url {
            if let proto = url.scheme, proto == "https" {
                config.collectorTLS = true
            }
            if let host = url.host {
                config.collectorHost = host
            }
            if let port = url.port {
                config.collectorPort = port
            }
            if let auth = self.auth {
                config.auth = auth
            }
        }
        return config
    }
}
