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

enum CentralConfigResponse : Int {
    case ok = 200,
    case not_modified = 304,
    case forbidden = 403,
    case not_found = 404
    case unavailable = 503,
}

class AgentConfigManager {
    static let LOG_LABEL = "co.elastic.centralConfigFetcher"
    static let ETAG_KEY = "elastic.central.config.etag"
    static let MAXAGE_KEY = "elastic.central.config.etag"

    let logger : Logger
    let centralConfig : CentralConfig
    let resource: Resource
    let configuration : AgentConfiguration
    let serviceEnvironment : String
    let serviceName : String
    let fetchQueue = DispatchQueue(label: "co.elastic.centralConfigFetch")
    let fetchTimer : DispatchSourceTimer
    var task : URLSessionDataTask? = nil
    
    var etag : String? {
        get {
            UserDefaults.standard.object(forKey: ETAG_KEY) as? String
        }
        set(etag) {
            UserDefaults.standard.setValue(etag, forKey:   ETAG_KEY)
        }
    }

    var maxAge : String? {
        get {
            UserDefaults.standard.object(forKey: MAXAGE_KEY) as? String
        }
        
        set(maxAge) {
            UserDefaults.standard.setValue(maxAge, forKey: MAXAGE_KEY)
        }
    }
    
    init(resource: Resource, config: AgentConfiguration, logger: Logging.Logger = Logger(label: Self.LOG_LABEL) { _ in
        SwiftLogNoOpLogHandler()
    })) {
        self.resource = resource
        self.configuration = config
        self.logger = logger
        
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
        
        DispatchSource.makeTimerSource(flags: DispatchSource.TimerFlags(), queue: pushMetricQueue)
        fetchTimer.setEventHandler { [weak self] in
            autoreleasepool {
                guard let self = self else {
                    return
                }
                
                self.fetch()
                
            }
        }
        fetchTimer.schedule(deadline: .now() + 60, repeating: 60)
        fetchTimer.activate()
    }
    
    deinit {
        fetchTimer.suspend()
        if !fetchTimer.isCancelled {
            fetchTimer.cancel()
            fetchTimer.resume()
        }
    }
    
    func parseMaxAge(cacheControl : String) -> Int {
        cacheControl.ranges(of: /max-age\s*=\s*(\d+)/)
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
            request.setValue(self.etag, forHTTPHeaderField: "ETag")
            
            if let auth = configuration.auth {
                request.setValue(auth, forHTTPHeaderField: "Authorization")
            }
            
            task = URLSession.shared.dataTask(with: request  ,completionHandler: { data, response, error in
                if let error = error {
                    logger.error(error.localizedDescription)
                    return
                }
    
                if let response = response as? HTTPURLResponse {

                    if CentralConfigResponse(response.statusCode) == .ok {
                        if let data = data {
                            self.centralConfig.config = String(data: data, encoding: .utf8)
                            
                            self.etag = response.value(forHTTPHeaderField: "ETag")
                            self.maxAge = response.value(forHTTPHeaderField: "Cache-Control")
                        }
                    } else {
                        switch CentralConfigResponse(response.statusCode) {
                        case .forbidden:
                            logger.debug("Central configuration is disabled. Set kibana.enabled: true in your APM Server configuration.")
                            break
                        case .not_found:
                            logger.debug("This APM Server does not support central configuration. Update to APM Server 7.3+")
                            break
                        case .not_modified:
                            logger.debug("Central config did not change.")
                            break
                        case .unavailable:
                            logger.error("Remote configuration is not available. Check the connection between APM Server and Kibana.")
                        default:
                            logger.error("Unexpected status code (\(response.statusCode)) received.")
                        }
                    }
                }
                
            })
            task?.resume()
        }
        
    }
}
