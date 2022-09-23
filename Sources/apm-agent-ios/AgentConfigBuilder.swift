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
    var host : String?
    var port : Int?
    var tls : Bool?
    var secretToken : String?
    
    public init() {}
    
    public func withURL(_ url: URL) -> Self {
        self.url = url
        return self
    }
    
    public func withHost(_ host: String) -> Self {
        self.host = host
        return self
    }
    
    public func withPort(_ port: Int) -> Self {
        self.port = port
        return self
    }
    
     public func withTLS(_ tls: Bool) -> Self {
        self.tls = tls
        return self
    }
    
    public func withSecretToken(_ token: String) ->Self {
        self.secretToken = secretToken
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
            } else {
                if config.collectorTLS {
                    config.collectorPort = 443
                } else {
                    config.collectorPort = 80
                }
            }
            
            if let secret = secretToken {
                config.secretToken = secret
            }
            
            if let host = self.host {
                config.collectorHost = host
            }
            
            if let port = self.port {
                config.collectorPort = port
            }
            
            if let tls = self.tls {
                config.collectorTLS = tls 
            }
        }
        return config
    }
}
