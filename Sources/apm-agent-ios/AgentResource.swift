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
#if os(watchOS)
    import WatchKit
#elseif os(macOS)
    import AppKit
#else
    import UIKit
#endif
import ResourceExtension
import OpenTelemetryApi
import OpenTelemetrySdk

public class AgentResource {
    public static func get() -> Resource {
        let defaultResource = DefaultResources().get()
        var overridingAttributes = [
            ResourceAttributes.telemetrySdkName.rawValue: AttributeValue.string("iOS")
        ]

        let osDataSource = OperatingSystemDataSource()
        overridingAttributes[ResourceAttributes.telemetrySdkVersion.rawValue] = AttributeValue.string("semver:\(Agent.ELASTIC_SWIFT_AGENT_VERSION)")
        overridingAttributes[ResourceAttributes.processRuntimeName.rawValue] = AttributeValue.string(osDataSource.name)
        overridingAttributes[ResourceAttributes.processRuntimeVersion.rawValue] = AttributeValue.string(osDataSource.version)
        if let deviceId = AgentResource.identifier() {
            overridingAttributes[ElasticAttributes.deviceIdentifier.rawValue] = AttributeValue.string(deviceId)
        }
        let appDataSource = ApplicationDataSource()

        if let build = appDataSource.build {
            if let version = appDataSource.version {
                overridingAttributes[ResourceAttributes.serviceVersion.rawValue] = AttributeValue.string(version)
                overridingAttributes[ElasticAttributes.serviceBuild.rawValue] = AttributeValue.string(build)
            } else {
                overridingAttributes[ResourceAttributes.serviceVersion.rawValue] = AttributeValue.string(build)
            }
        } else if let version = appDataSource.version {
            overridingAttributes[ResourceAttributes.serviceVersion.rawValue] = AttributeValue.string(version)

        }

        overridingAttributes[ResourceAttributes.deploymentEnvironment.rawValue] = AttributeValue.string("default")

        return defaultResource.merging(other: Resource.init(attributes: overridingAttributes))
    }

    static private func identifier() -> String? {
        #if os(watchOS)
            if #available(watchOS 6.3, *) {
                return WKInterfaceDevice.current().identifierForVendor?.uuidString
            } else {
                return nil
            }
        #elseif os(macOS)
            return nil
        #else
            return UIDevice.current.identifierForVendor?.uuidString

        #endif
    }

}
