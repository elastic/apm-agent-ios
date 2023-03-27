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

class AgentConfigManager {
    let centralConfig : CentralConfig
    let resource: Resource
    let configuration : AgentConfiguration
    let serviceEnvironment : String
    let serviceName : String
    var task : URLSessionDataTask? = nil
    
    init(resource: Resource, config: AgentConfiguration) {
        self.resource = resource
        self.configuration = config
        
        switch resource.attributes[ResourceAttributes.deploymentEnvironment.rawValue] {
        case let .string(value) :
            serviceEnvironment = value
            break
        default:
            serviceEnvironment = ""
            break;
        }
        
        switch resource.attributes[ResourceAttributes.serviceName.rawValue] {
        case let .string(value):
                serviceName = value
                break;
            default:
                serviceName = ""
        }
        
        self.centralConfig = CentralConfig(resource, config: config)
    }
    
    func fetch() {
        if let task = self.task {
            task.cancel()
        }
        var components = configuration.urlComponents()
        
        components.path = "/config/v1/agents"
        
        components.queryItems = [URLQueryItem(name: "service.name", value: serviceName), URLQueryItem(name: "service.environment", value: serviceEnvironment)]
        
        if let url = components.url {
            var request = URLRequest(url: url)
            
            request.cachePolicy = .useProtocolCachePolicy
            
            if let auth = configuration.auth {
                request.setValue(auth, forHTTPHeaderField: "Authorization")
            }
            
            task = URLSession.shared.dataTask(with: request  ,completionHandler: { data, response, error in
                if let _ = error {
                    // retry?
                    return
                }
    
                if let response = response as? HTTPURLResponse {
                    
                    
//                    if let max_age = response.allHeaderFields["Cache-Control"] as? TimeInterval {
//                        self.centralConfig.maxAge = Date(timeIntervalSinceNow:max_age)
//                    }
                    
                    if response.statusCode != 304 {
                        
                        if let data = data {
                            self.centralConfig.config = String(data: data, encoding: .utf8)
                        }
                    }
                }
                
            })
            task?.resume()
        }
        
    }
}
