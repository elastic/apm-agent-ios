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

  static let etagKey = "elastic.central.config.etag"
  static let maxAgeKey = "elastic.central.config.maxAge"
  static let defaultMaxAge: TimeInterval = 60.0
  let fetchQueue = DispatchQueue(label: "co.elastic.centralConfigFetch")
  let fetchTimer: DispatchSourceTimer
  let logger: Logger

  let serviceEnvironment: String
  let serviceName: String
  let config: AgentConfiguration
  var task: URLSessionDataTask?
  let callback: (Data) -> Void

  var etag: String? {
    get {
      UserDefaults.standard.object(forKey: Self.etagKey) as? String
    }
    set(etag) {
      UserDefaults.standard.setValue(etag, forKey: Self.etagKey)
    }
  }

  var maxAge: TimeInterval? {
    get {
      UserDefaults.standard.object(forKey: Self.maxAgeKey) as? TimeInterval
    }

    set(maxAge) {
      fetchTimer.schedule(deadline: .now() + (maxAge ?? Self.defaultMaxAge),
                          repeating: maxAge ?? Self.defaultMaxAge )
      UserDefaults.standard.setValue(maxAge, forKey: Self.maxAgeKey)
    }
  }

  init(serviceName: String,
       environment: String,
       agentConfig: AgentConfiguration,
       _ callback: @escaping (Data) -> Void,
       _ logger: Logging.Logger = Logging.Logger(label: "co.elastic.centralConfigFetcher") { _ in
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
    fetchTimer.schedule(deadline: .now(), repeating: self.maxAge ?? Self.defaultMaxAge )
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

  static func parseMaxAge(cacheControl: String) -> TimeInterval {
    let search = #"max-age\s*=(?<maxage>\d+)"#
    var regex: NSRegularExpression
    do {
      regex = try NSRegularExpression(pattern: search, options: .caseInsensitive)
    } catch {
      return Self.defaultMaxAge
    }

    let matches = regex.matches(in: cacheControl, range: NSRange(location: 0, length: cacheControl.count))

    guard let match = matches.first else { return Self.defaultMaxAge }

    let range = match.range(withName: "maxage")

    return TimeInterval((cacheControl as NSString).substring(with: range)) ?? Self.defaultMaxAge

  }

  func buildCentralConfigRequest() -> URLRequest? {
    var components = config.managementUrlComponents()

    components.queryItems = [URLQueryItem(name: "service.name", value: serviceName),
                             URLQueryItem(name: "service.environment", value: serviceEnvironment)]
    if let url = components.url {
      var request = URLRequest(url: url)

      request.setValue(self.etag, forHTTPHeaderField: "ETag")

      if let auth = config.auth {
        request.setValue(auth, forHTTPHeaderField: "Authorization")
      }
      return request
    }
    return nil
  }

  func fetch() {
    self.task?.cancel()

    if let request = buildCentralConfigRequest() {

      task = URLSession.shared.dataTask(with: request, completionHandler: { data, response, error in
        if let error = error {
          self.logger.error("\(error.localizedDescription)")
          return
        }

        if let response = response as? HTTPURLResponse {
          switch CentralConfigResponse(rawValue: response.statusCode) {
          case .okay:
            if let data = data {

              self.callback(data)

              self.etag = response.allHeaderFields["ETag"] as? String
              if let cacheControl = response.allHeaderFields["Cache-Control"] as? String {
                self.maxAge = Self.parseMaxAge(cacheControl: cacheControl)
              }
            }
          case .forbidden:
            self.logger.debug(
                          """
                          Central configuration is disabled. \
                          Set kibana.enabled: true in your APM Server configuration.
                          """)
          case .notFound:
            self.logger.debug(
                          """
                          This APM Server does not support central configuration. \
                          Update to APM Server 7.3+.
                          """)
          case .notModified:
            self.logger.debug("Central config did not change.")
          case .unavailable:
            self.logger.error(
                          """
                          Remote configuration is not available. \
                          Check the connection between APM Server and Kibana.
                          """)
          default:
            self.logger.error("Unexpected status code (\(response.statusCode)) received.")
          }
        }
      })
      task?.resume()
    }
  }
}
