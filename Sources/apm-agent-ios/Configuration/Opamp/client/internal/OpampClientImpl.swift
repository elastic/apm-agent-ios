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
public class OpampClientImpl : OpampClient, RequestServiceCallback, Supplier {
  public typealias Supply = OpampRequest
  private let requestService: RequestService
  private let clientState: OpampClientState
  private let runningLock = NSLock()
  private var isRunning = false
  private var isStopped = false
  private var callback: (any OpampClientCallback)?
  public static func create(
    requestService: RequestService,
    clientState: OpampClientState
  ) -> OpampClient {
    OpampClientImpl(requestService: requestService, clientState: clientState)
  }
  
  internal init(
  requestService: RequestService,
  clientState: OpampClientState)
  {
    self.requestService = requestService
    self.clientState = clientState
  }

  public func start(_ callback: any OpampClientCallback) {
    runningLock.lock()
    defer { runningLock.unlock() }
    
    if(!isRunning) {
      self.callback = callback
//      /*observeStateChange*/()
//      disableCompression()
      self.requestService.start(callback: self, request: self)
      self.requestService.sendRequest()
    }
  }

  public func get() -> OpampRequest {


  }

  public func stop() {
    runningLock.lock()
    defer {
      runningLock.unlock()
    }
    if (isRunning && !isStopped) {
      isStopped = true
      prepareDisconnectRequest()
      requestService.stop()
    }
  }

  public func setRemoteConfigStatus(_ remoteConfigStatus: Opamp_Proto_RemoteConfigStatus) {
    self.clientState.remoteConfigStatusState.value = remoteConfigStatus
  }

  // internal

  private func handleResponse(response: Opamp_Proto_ServerToAgent) {
    //handle errorResponse
    let reportFullState = Opamp_Proto_ServerToAgentFlags.reportFullState.rawValue
    if((response.flags & UInt64(reportFullState)) == reportFullState) {
      // disableCompression
    }

    handleAgentIdentification(response)

    if (response.hasRemoteConfig) {
      callback?.onMessage(client: self, message: OpampMessage(remoteConfig: response.remoteConfig))
    }
  }

  private func handleAgentIdentification(_ response: Opamp_Proto_ServerToAgent) {
    if (response.hasAgentIdentification) {
      if !response.agentIdentification.newInstanceUid.isEmpty, let newInstanceUid = UUID(
        from: response.agentIdentification.newInstanceUid
        ) {
        clientState.instanceUidState.value = newInstanceUid

      }
    }
  }

  // Request Service Callbacks

  public func onConnectionSuccess() {
    callback?.onConnect(client: self)
  }

  public func onConnectionFailure(error: any Error, retryAfter: TimeInterval) {
    callback?.onConnectFailed(client: self, error: error, retryAfter: retryAfter)
    // preserveFailedReqeustRecipe
  }

  public func onRequestSuccess(response: OpampResponse) {
    clientState.sequenceNumberState.increment()
    handleResponse(response: response.serverToAgent)
  }

  public func onRequestFailed(error: any Error, retryAfter: TimeInterval) {
    callback?
      .onErrorResponse(client: self, error: error, retryAfter: retryAfter);
    preserveFailedRequestRecipe();
  }

}
