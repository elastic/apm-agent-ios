// Copyright © 2021 Elasticsearch BV
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
import UIKit
import ResourceExtension
import OpenTelemetryApi
import OpenTelemetrySdk

public class AgentResource  {
    public static func get() -> Resource {
        let defaultResource = DefaultResources().get()
        var overridingAttributes = [
            ResourceAttributes.telemetrySdkName.rawValue :  AttributeValue.string("iOS"),
        ]
        
        
        overridingAttributes[ResourceAttributes.telemetrySdkVersion.rawValue] = AttributeValue.string(Agent.ELASTIC_SWIFT_AGENT_VERSION)
                
        if let deviceId = UIDevice.current.identifierForVendor?.uuidString {
            overridingAttributes["device.id"] = AttributeValue.string(deviceId)
        }
        
        return defaultResource.merging(other: Resource.init(attributes:overridingAttributes))
    }
}
