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

public struct AgentToServerAppenders {
  private let agentDescriptionAppender: AgentDescriptionAppender
  private let effectiveConfigAppender: EffectiveConfigAppender
  private let remoteConfigStatusAppender: RemoteConfigStatusAppender
  private let sequenceNumberAppender: SequenceNumberAppender
  private let capabilitiesAppender: CapabilitiesAppender
  private let instanceUidAppender: InstanceUidAppender
  private let flagAppender: FlagsAppender
  private let agentDisconnectAppender: AgentDisconnectAppender
  public let allAppenders: [FieldType: AgentToServerAppender]


  internal init(
    agentDescriptionAppender: AgentDescriptionAppender,
    effectiveConfigAppender: EffectiveConfigAppender,
    remoteConfigStatusAppender: RemoteConfigStatusAppender,
    sequenceNumberAppender: SequenceNumberAppender,
    capabilitiesAppender: CapabilitiesAppender,
    instanceUidAppender: InstanceUidAppender,
    flagAppender: FlagsAppender,
    agentDisconnectAppender: AgentDisconnectAppender
  ) {
    self.agentDescriptionAppender = agentDescriptionAppender
    self.effectiveConfigAppender = effectiveConfigAppender
    self.remoteConfigStatusAppender = remoteConfigStatusAppender
    self.sequenceNumberAppender = sequenceNumberAppender
    self.capabilitiesAppender = capabilitiesAppender
    self.instanceUidAppender = instanceUidAppender
    self.flagAppender = flagAppender
    self.agentDisconnectAppender = agentDisconnectAppender
    allAppenders = [
      .AGENT_DESCRIPTION: self.agentDescriptionAppender,
      .EFFECTIVE_CONFIG: self.effectiveConfigAppender,
      .REMOTE_CONFIG_STATUS: self.remoteConfigStatusAppender,
      .SEQUENCE_NUMBER: self.sequenceNumberAppender,
      .CAPABILITIES: self.capabilitiesAppender,
      .INSTANCE_UID: self.instanceUidAppender,
      .FLAGS: self.flagAppender,
      .AGENT_DISCONNECT: self.agentDisconnectAppender,
    ]
  }
}
