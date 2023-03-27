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

class CentralConfig {
    static let CentralConfigKey = "elastic.central.configuration"
    
    
    public var config : String? {
        get {
            UserDefaults.standard.object(forKey: Self.CentralConfigKey) as? String
        }
        set(config) {
            UserDefaults.standard.setValue(config, forKey: Self.CentralConfigKey)
        }
    }
    
    private let serviceName : String
    private let serviceEnvironment : String
    private let configuration : AgentConfiguration
    init(_ resource: Resource, config: AgentConfiguration) {
        configuration = config
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
    }
}
