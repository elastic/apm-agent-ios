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
    case ok = 200
    case not_modified = 304
    case forbidden = 403
    case not_found = 40
    case unavailable = 503
}

class AgentConfigManager {
    static let ETAG_KEY = "elastic.central.config.etag"
    static let MAXAGE_KEY = "elastic.central.config.maxAge"

    public let agent : AgentConfiguration
    public let central : CentralConfig
    public let instrumentation : InstrumentationConfiguration

    let logger : Logger
    let resource: Resource
    let serviceEnvironment : String
    let serviceName : String
    let fetchQueue = DispatchQueue(label: "co.elastic.centralConfigFetch")
    let fetchTimer : DispatchSourceTimer
    var task : URLSessionDataTask? = nil
    
    var etag : String? {
        get {
            UserDefaults.standard.object(forKey: Self.ETAG_KEY) as? String
        }
        set(etag) {
            UserDefaults.standard.setValue(etag, forKey:   Self.ETAG_KEY)
        }
    }

    var maxAge : TimeInterval? {
        get {
            UserDefaults.standard.object(forKey: Self.MAXAGE_KEY) as? TimeInterval
        }
        
        set(maxAge) {
            fetchTimer.suspend()

            fetchTimer.schedule(deadline: .now() + (maxAge ?? 60.0), repeating: maxAge ?? 60.0 )
            fetchTimer.activate()

            UserDefaults.standard.setValue(maxAge, forKey: Self.MAXAGE_KEY)
        }
    }
    
    
    
    init(resource: Resource, config: AgentConfiguration, instrumentationConfig: InstrumentationConfiguration, logger: Logging.Logger = Logging.Logger(label: "co.elastic.centralConfigFetcher") { _ in
        SwiftLogNoOpLogHandler()
    }) {
        self.resource = resource
        self.agent = config
        self.instrumentation = instrumentationConfig
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
        
        self.central = CentralConfig(resource, config: config)
        
        fetchTimer = DispatchSource.makeTimerSource(flags: DispatchSource.TimerFlags(), queue: fetchQueue)
        fetchTimer.setEventHandler { [weak self] in
            autoreleasepool {
                guard let self = self else {
                    return
                }
                
                self.fetch()
            }
        }
        fetchTimer.schedule(deadline: .now(), repeating: self.maxAge ?? 60.0 )
        fetchTimer.activate()
    }
    
    deinit {
        fetchTimer.suspend()
        if !fetchTimer.isCancelled {
            fetchTimer.cancel()
            fetchTimer.resume()
        }
    }
    
    func parseMaxAge(cacheControl : String) -> TimeInterval {
        let range = cacheControl.range(of: #"max-age\s*=\s*(\d)"#, options: .regularExpression)
        if let range = range {
            return TimeInterval(cacheControl[range]) ?? 60.0
        }
        
        return  60.0

    }
    
    func fetch() {
        if let task = self.task {
            task.cancel()
        }
        var components = agent.urlComponents()
        
        components.path = "/config/v1/agents"
        
        components.queryItems = [URLQueryItem(name: "service.name", value: serviceName), URLQueryItem(name: "service.environment", value: serviceEnvironment)]
        
        if let url = components.url {
            var request = URLRequest(url: url)
            
            request.setValue(self.etag, forHTTPHeaderField: "ETag")
            
            if let auth = agent.auth {
                request.setValue(auth, forHTTPHeaderField: "Authorization")
            }
            
            task = URLSession.shared.dataTask(with: request  ,completionHandler: { data, response, error in
                if let error = error {
                    self.logger.error("\(error.localizedDescription)")
                    return
                }
    
                if let response = response as? HTTPURLResponse {

                    if CentralConfigResponse(rawValue: response.statusCode) == .ok {
                        if let data = data {
                            self.central.config = String(data: data, encoding: .utf8)
                            
                            self.etag = response.allHeaderFields["ETag"] as? String
                            if let cacheControl = response.allHeaderFields["Cache-Control"] as? String {
                                self.maxAge = self.parseMaxAge(cacheControl: cacheControl)
                            }
                        }
                    } else {
                        switch CentralConfigResponse(rawValue: response.statusCode) {
                        case .forbidden:
                            self.logger.debug("Central configuration is disabled. Set kibana.enabled: true in your APM Server configuration.")
                            break
                        case .not_found:
                            self.logger.debug("This APM Server does not support central configuration. Update to APM Server 7.3+")
                            break
                        case .not_modified:
                            self.logger.debug("Central config did not change.")
                            break
                        case .unavailable:
                            self.logger.error("Remote configuration is not available. Check the connection between APM Server and Kibana.")
                        default:
                            self.logger.error("Unexpected status code (\(response.statusCode)) received.")
                        }
                    }
                }
                
            })
            task?.resume()
        }
        
    }
}