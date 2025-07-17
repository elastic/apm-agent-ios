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

public struct OpampClientBuilder {
//  private let requestService: RequestService

//  public func build() -> OpampClient {
//    return OpampClient()
//  }



  /// Sets an implementation of a `RequestService` to handle the request's sending process.
  /// - Parameter requestService: the RequestService Implementation
  /// - Returns Self
  public func setRequestService(requestService _: RequestService) -> Self {
//    self.requestService = requestService
    return self
  }

  public func setInstsanceUid(instanceUid _: Data) -> Self {
    
    return self
  }

  public func setServiceName(serviceName _: String) -> Self {

    return self
  }

  public func setServiceNamespace(serviceNamespace _: String) -> Self {

    return self
  }

  public func setServiceVersion(serviceVersion _: String) -> Self {

    return self
  }

  public func setServiceEnvironment(serviceEnvironment _: String) -> Self {
    
    return self
  }

  public func enableRemoteConfig() -> Self {

    return self
  }

  public func addIdentifyingAttribute(key: String, value: AttributeValue) -> Self {
      var agentDescription = Opamp_Proto_AgentDescription()
    agentDescription.identifyingAttributes
      .append(OpampClientBuilder.createKeyValue(key:key, attributeValue:value))
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
