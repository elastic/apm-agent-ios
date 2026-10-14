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
import ResourceExtension
import OpenTelemetryApi
import OpenTelemetrySdk
import os.log

public class AgentResource {
  public static func get() -> Resource {
    get(useLegacyAttributeNames: false)
  }

  static let emptyInterceptedResourceMessage =
    "addResourceInterceptor: an interceptor returned a resource with no attributes; "
    + "EDOT iOS keeps the resource from before interception. Resource attribute keys must be "
    + "non-empty, at most 255 characters, and printable ASCII; one invalid key leaves a "
    + "Resource with no attributes."

  private static let logger = OSLog(subsystem: "co.elastic.ElasticApm", category: "Resource")

  /// The resource the agent installs on every provider and passes to central
  /// configuration: the detected attributes merged with
  /// `OTEL_RESOURCE_ATTRIBUTES`, then passed through the configured resource
  /// interceptors. Their output is final unless it has no attributes while
  /// the input had some; then the input is kept and an error is logged.
  static func get(
    configuration: AgentConfiguration,
    environmentResource: Resource = AgentEnvResource.get()
  ) -> Resource {
    let resource = get(useLegacyAttributeNames: configuration.useLegacyAttributeNames)
      .merging(other: environmentResource)
    let intercepted = configuration.resourceInterceptor.intercept(resource)
    if intercepted.attributes.isEmpty, !resource.attributes.isEmpty {
      os_log("%{public}@", log: logger, type: .error, emptyInterceptedResourceMessage)
      return resource
    }
    return intercepted
  }

  static func get(useLegacyAttributeNames: Bool) -> Resource {
    let defaultResource = DefaultResources().get()
    var overridingAttributes = [
      SemanticConventions.Telemetry.sdkName.rawValue: AttributeValue
        .string("iOS")
    ]

    let osDataSource = OperatingSystemDataSource()
    overridingAttributes[SemanticConventions.Telemetry.sdkVersion.rawValue] =
      AttributeValue.string(
        useLegacyAttributeNames
          ? LegacyAttributeNames.telemetrySDKVersionPrefix
            + ElasticApmAgent.elasticSwiftAgentVersion
          : ElasticApmAgent.elasticSwiftAgentVersion
      )
    overridingAttributes[SemanticConventions.Process.runtimeName.rawValue] = AttributeValue
      .string(osDataSource.name)
    overridingAttributes[SemanticConventions.Process.runtimeVersion.rawValue] =
      AttributeValue.string(osDataSource.version)
    let installationId = InstallationIdProvider().get()
    overridingAttributes[SemanticConventions.App.installationId.rawValue] = AttributeValue
      .string(installationId)
    let appDataSource = ApplicationDataSource()

    if let build = appDataSource.build {
      if let version = appDataSource.version {
        overridingAttributes[SemanticConventions.Service.version.rawValue] = AttributeValue
          .string(version)
        overridingAttributes[
          useLegacyAttributeNames
            ? LegacyAttributeNames.serviceBuild
            : SemanticConventions.App.buildId.rawValue
        ] = AttributeValue.string(build)
      } else {
        overridingAttributes[SemanticConventions.Service.version.rawValue] = AttributeValue
          .string(build)
      }
    } else if let version = appDataSource.version {
      overridingAttributes[SemanticConventions.Service.version.rawValue] = AttributeValue.string(version)

    }

    overridingAttributes[SemanticConventions.Deployment.environmentName.rawValue] = AttributeValue
      .string("default")

    return defaultResource.merging(other: Resource.init(attributes: overridingAttributes))
  }
}
