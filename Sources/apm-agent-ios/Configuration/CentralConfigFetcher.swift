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

class CentralConfigFetcher {
    
    static let ETAG_KEY = "elastic.central.config.etag"
    static let MAXAGE_KEY = "elastic.central.config.maxAge"
    static let DEFAULT_MAXAGE : TimeInterval = 60.0
    let fetchQueue = DispatchQueue(label: "co.elastic.centralConfigFetch")
    let fetchTimer : DispatchSourceTimer
    let logger : Logger

    let serviceEnvironment : String
    let serviceName : String
    let config : AgentConfiguration
    var task : URLSessionDataTask? = nil
    let callback : (Data) -> Void
    
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
            fetchTimer.schedule(deadline: .now() + (maxAge ?? Self.DEFAULT_MAXAGE), repeating: maxAge ?? Self.DEFAULT_MAXAGE )
            UserDefaults.standard.setValue(maxAge, forKey: Self.MAXAGE_KEY)
        }
    }
    
    
    init(serviceName: String, environment: String, agentConfig: AgentConfiguration, _ callback: @escaping (Data) -> Void, _ logger: Logging.Logger = Logging.Logger(label: "co.elastic.centralConfigFetcher") { _ in
        SwiftLogNoOpLogHandler()
    }) {
        self.serviceName = serviceName
        self.serviceEnvironment = environment
        self.callback = callback
        self.config = agentConfig
        self.logger  = logger
        fetchTimer = DispatchSource.makeTimerSource(flags: DispatchSource.TimerFlags(), queue: fetchQueue)
        fetchTimer.setEventHandler { [weak self] in
            autoreleasepool {
                guard let self = self else {
                    return
                }
                self.fetch()
            }
        }
        fetchTimer.schedule(deadline: .now(), repeating: self.maxAge ?? Self.DEFAULT_MAXAGE )
        fetchTimer.activate()
    }
    
    func scheduleFetchTimer(maxAge: TimeInterval) {
        
    }
    
    deinit {
        fetchTimer.suspend()
        if !fetchTimer.isCancelled {
            fetchTimer.cancel()
            fetchTimer.resume()
        }
    }
    
    static func parseMaxAge(cacheControl : String) -> TimeInterval {
        let search = #"max-age\s*=(?<maxage>\d+)"#
        var regex : NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: search, options:.caseInsensitive)
        } catch {
            return Self.DEFAULT_MAXAGE
        }
        
        let matches = regex.matches(in: cacheControl, range: NSRange(location: 0, length: cacheControl.count))
        
        guard let match = matches.first else { return Self.DEFAULT_MAXAGE }
        
        let range = match.range(withName: "maxage")
        
        return TimeInterval((cacheControl as NSString).substring(with: range)) ?? Self.DEFAULT_MAXAGE

    }

    
    func fetch() {
        if let task = self.task {
            task.cancel()
        }
        
        
        var components = config.urlComponents()
        
        components.path = "/config/v1/agents"
        
        components.queryItems = [URLQueryItem(name: "service.name", value:  serviceName), URLQueryItem(name: "service.environment", value: serviceEnvironment)]
        
        if let url = components.url {
            var request = URLRequest(url: url)
            
            request.setValue(self.etag, forHTTPHeaderField: "ETag")
            
            if let auth = config.auth {
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
                            
                            self.callback(data)
                            
                            self.etag = response.allHeaderFields["ETag"] as? String
                            if let cacheControl = response.allHeaderFields["Cache-Control"] as? String {
                                self.maxAge = Self.parseMaxAge(cacheControl: cacheControl)
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
