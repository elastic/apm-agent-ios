//
//  Copyright © 2025  Elasticsearch BV
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
import os.log

public class OpampHttpReqeustService: RequestService {
  private let httpClient: OpampHttpClient
  private let requestDelay: TimeInterval
  private let retryDelay: TimeInterval
  private let requestQueue = DispatchQueue(
    label: "com.elastic.apm.agent.opamp.http.request.timer",
    qos: .utility)
  private let lock = NSLock()
  private let requestTimer: DispatchSourceTimer

  private var callback: RequestServiceCallback?
  private var request: OpampRequest?

  private var isRunning = false
  private var isStopped = false

  private static let defaultURL = URL(string: "http://localhost:4320/v1/opamp")!

  init(
    httpClient: OpampHttpClient = OpampHttpClient(url: defaultURL),
    requestDelay: TimeInterval = 30.0,
    retryDelay: TimeInterval = 30.0,
  ) {
    self.httpClient = httpClient
    self.requestDelay = requestDelay
    self.retryDelay = retryDelay
    self.requestTimer = DispatchSource.makeTimerSource(queue: requestQueue)
    requestTimer.setEventHandler { [weak self] in
      autoreleasepool {
        guard let self = self else {
          return
        }
        self.lock.lock()
        defer { self.lock.unlock() }
        self.doSendRequest()
      }
    }

    self.requestTimer
      .schedule(
        deadline: .now() + requestDelay,
        repeating: requestDelay
      )
  }

  public func start(callback: RequestServiceCallback, request: OpampRequest) {
    lock.lock()
    defer { lock.unlock() }
    if (isStopped) {
      os_log("OpampHttpRequestService has been stopped.")
      return
    }
    if (isRunning) {
      os_log("OpampHttpReqeustService is already running.")
      return
    }
    self.callback = callback
    self.request = request
    self.requestTimer.activate()
    isRunning = true
  }

  public func sendRequest() {
    lock.lock()
    defer { lock.unlock() }
    self.requestTimer.schedule(deadline: .now(), repeating: self.requestDelay)
  }

  public func stop() {
    lock.lock()
    defer { lock.unlock() }
    if (!isRunning || isStopped) {
      return
    }
    isStopped = true
    requestTimer.schedule(deadline: .now(), repeating: .never)
    requestTimer.cancel()
  }

  private func doSendRequest() {
    // get agentToServer
    self.lock.lock()
    defer { self.lock.unlock() }
    if let request = self.request {
      httpClient.send(
opampRequest: request,
 completion: {
        [weak self]
        result in

   guard let self = self else { return }
        switch result {
        case let .success((serverToAgent, httpResponse)):
          if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
            DispatchQueue.main.async { [weak self, serverToAgent] in
                guard let self = self else { return }
                self.callback?.onRequestSuccess(response: serverToAgent)
              }
          } else {
            if httpResponse.statusCode == 503 || httpResponse.statusCode == 429 {
              if let retryAfterHeader = httpResponse.value(forHTTPHeaderField:"Retry-After") {
                let retryAfter: TimeInterval = Double(retryAfterHeader) ?? self.retryDelay // todo: parse RFC_1123 date format
              }
            }

            let error = NSError(
              domain: HTTPURLResponse
                .localizedString(forStatusCode: httpResponse.statusCode),
              code: httpResponse.statusCode,
                )

            DispatchQueue.main.async { [weak self, error] in
              guard let self = self else { return }
              self.callback?.onRequestFailed(error: error, retryAfter: self.retryDelay)
            }
          }
        case let .failure(error):
          DispatchQueue.main.async { [weak self, error] in
            guard let self = self else { return }
            self.callback?.onConnectionFailure(error: error, retryAfter: self.retryDelay) //todo: implement back-off
          }
        }
      })
    }
  }
}
