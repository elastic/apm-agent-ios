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
import OpenTelemetryApi
import OpenTelemetrySdk

public extension OpampClientImpl {
  class Builder : OpampClientBuilderInterface {
    public typealias Client = OpampClientImpl
    private let remoteConfigStatusState = OpampRemoteConfigStatusState()
    private let sequenceNumberState = OpampSequenceNumberState()
    private let agentDescriptionState = OpampAgentDescriptionState()
    private let capabilitiesState = OpampCapabilitiesState()
    private let instanceUidState = OpampInstanceUidState()
    private let effectiveConfigState = OpampEffectiveConfigState()
    
    public func build(requestService: some RequestService) -> Client {
      let clientState = OpampClientState(
        remoteConfigStatusState: remoteConfigStatusState,
        sequenceNumberState: sequenceNumberState,
        agentDescriptionState: agentDescriptionState,
        capabilitiesState: capabilitiesState,
        instanceUidState: instanceUidState,
        effectiveConfigState: effectiveConfigState
      )
      return OpampClientImpl.create(
        requestService: requestService,
        clientState: clientState
      )
    }

    @discardableResult
    public func setInstsanceUid(_ instanceUid : UUID) -> Self {
      instanceUidState.value = instanceUid
      return self
    }

    @discardableResult
    public func setServiceName(_ serviceName: String) -> Self {
      return addIdentifyingAttribute(
        key: ResourceAttributes.serviceName.rawValue,
        value: .string(serviceName))
    }

    @discardableResult
    public func setServiceNamespace(_ serviceNamespace: String) -> Self {
      return addIdentifyingAttribute(
        key: ResourceAttributes.serviceNamespace.rawValue,
        value: .string(serviceNamespace)
      )
    }

    @discardableResult
    public func setServiceVersion(_ serviceVersion: String) -> Self {
      return addIdentifyingAttribute(
        key: ResourceAttributes.serviceVersion.rawValue,
        value: .string(serviceVersion))
    }

    @discardableResult
    public func setServiceEnvironment(_ serviceEnvironment: String) -> Self {
      return addIdentifyingAttribute(
        key: "deployment.environment.name" ,
        value: .string(serviceEnvironment)
      )
    }

    @discardableResult
    public func enableRemoteConfig() -> Self {
      capabilitiesState.add(capabilities: .acceptsRemoteConfig)
      capabilitiesState.add(capabilities: .reportsRemoteConfig)
      return self
    }

    @discardableResult
    public func enableEffectiveConfigReporting() -> Self {
      capabilitiesState.add(capabilities: .reportsEffectiveConfig)
      return self
    }

    @discardableResult
    public func setEffectiveConfigState() -> Self {
      
      return self
    }

    public func addIdentifyingAttribute(key: String, value: AttributeValue) -> Self {
      agentDescriptionState.value.identifyingAttributes
        .append(OpampClientImpl.Builder.createKeyValue(key:key, attributeValue:value))
      return self
    }

    private static func createKeyValue(key: String, attributeValue: AttributeValue) -> Opamp_Proto_KeyValue {
      var keyValue = Opamp_Proto_KeyValue()
      keyValue.key = key
      switch attributeValue {
      case let .string(value):
        keyValue.value.stringValue = value
      case let .bool(value):
        keyValue.value.boolValue = value
      case let .int(value):
        keyValue.value.intValue = Int64(value)
      case let .double(value):
        keyValue.value.doubleValue = value
        
      case let .set(value):
        keyValue.value.kvlistValue.values = value.labels.map {
          return createKeyValue(key: $0, attributeValue: $1)
        }
      case let .array(value):
        keyValue.value.arrayValue.values = value.values.map {
          return toProtoAnyValue(attributeValue: $0)
        }
      case let .stringArray(value):
        keyValue.value.arrayValue.values = value.map {
          return toProtoAnyValue(attributeValue: .string($0))
        }
      case let .boolArray(value):
        keyValue.value.arrayValue.values = value.map {
          return toProtoAnyValue(attributeValue: .bool($0))
        }
      case let .doubleArray(value):
        keyValue.value.arrayValue.values = value.map {
          return toProtoAnyValue(attributeValue: .double($0))
        }
      case let .intArray(value):
        keyValue.value.arrayValue.values = value.map {
          return toProtoAnyValue(attributeValue: .int($0))
        }
      }
      return keyValue
    }
    
    private static func toProtoAnyValue(attributeValue: AttributeValue) -> Opamp_Proto_AnyValue {
      var anyValue = Opamp_Proto_AnyValue()
      switch attributeValue {
      case let .string(value):
        anyValue.stringValue = value
      case let .bool(value):
        anyValue.boolValue = value
      case let .int(value):
        anyValue.intValue = Int64(value)
      case let .double(value):
        anyValue.doubleValue = value
      case let .set(value):
        anyValue.kvlistValue.values = value.labels.map {
          return createKeyValue(key: $0, attributeValue: $1)
        }
      case let .array(value):
        anyValue.arrayValue.values = value.values.map {
          return toProtoAnyValue(attributeValue: $0)
        }
      case let .stringArray(value):
        anyValue.arrayValue.values = value.map {
          return toProtoAnyValue(attributeValue: .string($0))
        }
      case let .boolArray(value):
        anyValue.arrayValue.values = value.map {
          return toProtoAnyValue(attributeValue: .bool($0))
        }
      case let .intArray(value):
        anyValue.arrayValue.values = value.map {
          return toProtoAnyValue(attributeValue: .int($0))
        }
      case let .doubleArray(value):
        anyValue.arrayValue.values = value.map {
          return toProtoAnyValue(attributeValue: .double($0))
        }
      }
      return anyValue
    }
    internal init() {}
  }
}
