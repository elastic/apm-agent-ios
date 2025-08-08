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
  private static let CONSTANT_FIELDS = [
    FieldType.INSTANCE_UID,
    FieldType.SEQUENCE_NUMBER,
    FieldType.CAPABILITIES]
  private static let COMPRESSABLE_FIELDS = [
    FieldType.AGENT_DESCRIPTION,
    FieldType.EFFECTIVE_CONFIG,
    FieldType.REMOTE_CONFIG_STATUS,
  ]
  public typealias Supply = OpampRequest
  private let requestService: RequestService
  private let recipeManager: RecipeManager
  private let clientState: OpampClientState
  private let appenders: AgentToServerAppenders
  private let runningLock = NSLock()
  private var isRunning = false
  private var isStopped = false
  private var callback: (any OpampClientCallback)?
  public static func create(
    requestService: RequestService,
    clientState: OpampClientState
  ) -> OpampClient {

    OpampClientImpl(
      requestService: requestService,
      appenders: AgentToServerAppenders(
        agentDescriptionAppender: AgentDescriptionAppender(
          agentDescriptor: clientState.agentDescriptionState
        ),
        effectiveConfigAppender: EffectiveConfigAppender(
          effectiveConfig: clientState.effectiveConfigState
        ),
        remoteConfigStatusAppender: RemoteConfigStatusAppender(
          config: clientState.remoteConfigStatusState
        ),
        sequenceNumberAppender: SequenceNumberAppender(
          sequenceNumber: clientState.sequenceNumberState
        ),
        capabilitiesAppender: CapabilitiesAppender(
          capabilities:clientState.capabilitiesState),
        instanceUidAppender: InstanceUidAppender(
          instanceUid:clientState.instanceUidState),
        flagAppender: FlagsAppender(),
        agentDisconnectAppender: AgentDisconnectAppender()
        ),
      clientState: clientState,
      recipeManager: RecipeManager(constFields: Self.CONSTANT_FIELDS)
      )
  }
  
  internal init(
  requestService: RequestService,
  appenders: AgentToServerAppenders,
  clientState: OpampClientState,
  recipeManager: RecipeManager)
  {
    self.requestService = requestService
    self.clientState = clientState
    self.recipeManager = recipeManager
    self.appenders = appenders
  }

  @objc public func onStateForFieldChanged(notifaction: Notification) {
    if let fieldType = notifaction.object as? FieldType {
      recipeManager.next().addField(fieldType)
    }
  }

  public func start(_ callback: any OpampClientCallback) {
    runningLock.lock()
    defer { runningLock.unlock() }
    
    if(!isRunning) {
      self.callback = callback
      NotificationCenter.default.addObserver(
self,
selector: #selector(onStateForFieldChanged),
                                             name: Notification
  .Name(
    Opamp.STATE_CHANGE_NOTIFICATION
  ),
object: nil
      )
      disableCompression()
      self.requestService.start(callback: self, request: self)
      self.requestService.sendRequest()
    }
  }

  public func get() -> OpampRequest {
    var agentToServer = Opamp_Proto_AgentToServer()
    for field in recipeManager.next().build().fields {
      appenders.allAppenders[field]?.append(to: &agentToServer)
    }
    return OpampRequest(agentToServer: agentToServer)

  }

  internal func prepareDisconnectRequest() {
    recipeManager.next().addField(.AGENT_DISCONNECT)
  }

  internal func preserveFailedRequestRecipe() {
    if let previous = recipeManager.previous() {
      recipeManager.next().merge(with: previous)
    }
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
      disableCompression()
    }

    handleAgentIdentification(response)

    if (response.hasRemoteConfig) {
      callback?.onMessage(client: self, message: OpampMessage(remoteConfig: response.remoteConfig))
    }
  }

  private func disableCompression() {
    recipeManager.next().addAllFields(Self.COMPRESSABLE_FIELDS)
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
    preserveFailedRequestRecipe()
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
