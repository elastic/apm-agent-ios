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

public class OpampHttpRequestService: RequestService {
  private let httpClient: OpampSender
  private let requestDelay: TimeInterval
  private let retryDelay: TimeInterval
  private let requestQueue = DispatchQueue(
    label: "com.elastic.apm.agent.opamp.http.request.timer",
    qos: .utility)
  private let lock = NSLock()
  private var retryModeEnabled = false
  private var exponentialBackoffSkips = 0
  private let requestTimer: DispatchSourceTimer

  private var callback: RequestServiceCallback?
  private var request: OpampRequest?

  public private(set) var isRunning = false
  public private(set) var isStopped = false

  internal static let defaultURL = URL(string: "http://localhost:4320/v1/opamp")!

  init(
    httpClient: OpampSender = OpampHttpSender(url: defaultURL),
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


  private func isSuccessful(_ response: URLResponse) -> Bool{
    if let httpResponse = response as? HTTPURLResponse {
      return httpResponse.statusCode >= 200 && httpResponse.statusCode < 300
    }
    return false
  }

  private func shouldUpdateRetryDelay(_ response: HTTPURLResponse) -> Bool {
      return response.statusCode == 429 || response.statusCode == 503
  }




  private func handleHttpError(_ response: URLResponse) {
    if let httpResponse = response as? HTTPURLResponse {
      var retryAfter: TimeInterval = retryDelay
      if shouldUpdateRetryDelay(httpResponse) {
        if let retryAfterHeader = httpResponse.value(forHTTPHeaderField:"Retry-After") {
          if let parsedRetryAfter =  Double(retryAfterHeader) {
            retryAfter = parsedRetryAfter
          } else if let parsedDate = OpampHttpDate.parse(dateString: retryAfterHeader) {
            retryAfter = parsedDate.timeIntervalSinceNow
          }
        }
      }
      let error = NSError(
        domain: HTTPURLResponse
          .localizedString(forStatusCode: httpResponse.statusCode),
        code: httpResponse.statusCode,
      )

      DispatchQueue.global().async { [weak self, error] in
        guard let self = self else { return }
        self.callback?.onRequestFailed(error: error, retryAfter: retryAfter)
      }
      enableRetryMode(retryAfter)

    }
  }


  private func enableRetryMode(_ retryAfter: TimeInterval) {
    if !retryModeEnabled {
      retryModeEnabled = true
      self.requestTimer
        .schedule(deadline: .now() + retryAfter, repeating: retryAfter)
    }
  }

  private func disableRetryMode() {
    if retryModeEnabled {
      retryModeEnabled = false
      self.requestTimer.schedule(deadline: .now() + self.requestDelay, repeating: self.requestDelay)

    }
  }


  private func handleErrorResponse(
    _ errorResponse: Opamp_Proto_ServerErrorResponse
  ) {
    switch errorResponse.type {
    case .unavailable:
      let retryAfter = errorResponse.retryInfo.retryAfterNanoseconds
      if retryAfter > 0 {
        enableRetryMode(TimeInterval.fromNanoseconds(Int64(retryAfter)))
      } else {
        incrementExponentialBackoff()
      }
    case .badRequest, .unknown, .UNRECOGNIZED(_):
      incrementExponentialBackoff()
    }
  }

  private func incrementExponentialBackoff() {
    if (exponentialBackoffSkips == 0) {
      exponentialBackoffSkips = 1;
    } else {
      exponentialBackoffSkips *= 2;
    }
    if (exponentialBackoffSkips >= 32) {
      exponentialBackoffSkips = 32;
    }
    enableRetryMode(retryDelay * Double(exponentialBackoffSkips))
  }

  private func resetExponentialBackoffSkips() {
    exponentialBackoffSkips = 0
    disableRetryMode()
  }

  private func handleNetworkError(_ error: Error) {
    incrementExponentialBackoff()
    DispatchQueue.global().async { [weak self, error] in
      guard let self = self else { return }
      self.callback?.onConnectionFailure(error: error, retryAfter: self.retryDelay)
    }
  }

  private func handleResponse(_ opampResponse: OpampResponse) {
    disableRetryMode()
    if opampResponse.serverToAgent.hasErrorResponse {
      handleErrorResponse(opampResponse.serverToAgent.errorResponse)
    }
    DispatchQueue.global().async { [weak self, opampResponse] in
      guard let self = self else { return }
      self.callback?.onRequestSuccess(response: opampResponse)
    }

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
        case let .success((opampResponse, urlResponse)):
          if isSuccessful(urlResponse) {
            resetExponentialBackoffSkips()
            handleResponse(opampResponse)
          } else {
            handleHttpError(urlResponse)
          }
        case let .failure(error):
          handleNetworkError(error)
        }
      })
    }
  }
}
