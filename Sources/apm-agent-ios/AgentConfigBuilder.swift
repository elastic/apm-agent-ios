// Copyright © 2022 Elasticsearch BV
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
import PersistenceExporter

public class AgentConfigBuilder {
  private var enableAgent: Bool?
  private var serverUrl: URL?
  private var exportUrl: URL?
  private var managementUrl: URL?
  private var enableRemoteManagement: Bool?
  private var auth: String?
  private var enableOpAPM: Bool = false
  private static let bearer = "Bearer"
  private static let api = "ApiKey"
  private var connectionType: AgentConnectionType = .http
  private var sampleRate = 1.0
  private var legacyAttributeNames = false

  private var spanFilters = [SignalFilter<ReadableSpan>]()
  private var logFilters = [SignalFilter<ReadableLogRecord>]()

  private var spanAttributeInterceptors: [AnyInterceptor<[String: AttributeValue]>] = []
  private var logRecordAttributeInterceptors: [AnyInterceptor<[String: AttributeValue]>] = []
  private var resourceInterceptors: [AnyInterceptor<Resource>] = []
  public init() {}

  public func disableAgent() -> Self {
    enableAgent = false
    return self
  }

  @available(
    *,
    deprecated,
    renamed: "withExportUrl",
    message: "Use withExportUrl(_:) for OTLP export and withManagementUrl(_:) for management."
  )
  public func withServerUrl(_ url: URL) -> Self {
    self.serverUrl = url
    return self
  }

  public func withExportUrl(_ url: URL) -> Self {
    self.exportUrl = url
    return self
  }

  public func withManagementUrl(_ url: URL) -> Self {
    self.managementUrl = url
    return self
  }

  @available(
    *,
    deprecated,
    message: "The legacy central configuration poll will be removed. Use useOpAMP() to select central configuration."
  )
  public func withRemoteManagement(_ enabled: Bool) -> Self {
    enableRemoteManagement = enabled
    return self
  }

  public func withSecretToken(_ token: String) -> Self {
    self.auth = "\(Self.bearer) \(token)"
    return self
  }

  public func useConnectionType(_ type: AgentConnectionType) -> Self {
    self.connectionType = type
    return self
  }

  public func useLegacyAttributeNames(_ enabled: Bool) -> Self {
    legacyAttributeNames = enabled
    return self
  }

  public func useOpAMP() -> Self {
    enableOpAPM = true
    return self
  }

  public func withApiKey(_ key: String) -> Self {
    self.auth = "\(Self.api) \(key)"
    return self
  }

  public func withSessionSampleRate(_ rate: Double) -> Self {
    sampleRate = min(max(rate, 0.0), 1.0)
    return self
  }

  public func addSpanFilter(_ shouldInclude: @escaping (any ReadableSpan) -> Bool) -> Self {
    spanFilters.append(SignalFilter<ReadableSpan>(shouldInclude))
    return self
  }

  public func addLogFilter(_ shouldInclude: @escaping (ReadableLogRecord) -> Bool) -> Self {
    logFilters.append(SignalFilter<ReadableLogRecord>(shouldInclude))
    return self
  }

  public func addSpanAttributeInterceptor(_ interceptor: some Interceptor<[String: AttributeValue]>) -> Self {
    self.spanAttributeInterceptors.append(AnyInterceptor(interceptor))
    return self
  }

  @_disfavoredOverload
  @available(iOS 16, *)
  public func addSpanAttributeInterceptor(_ interceptor: any Interceptor<[String: AttributeValue]>) -> Self {
    return addSpanAttributeInterceptor(AnyInterceptor(interceptor))
  }

  public func addLogRecordAttributeInterceptor(_ interceptor: some Interceptor<[String: AttributeValue]>) -> Self {
    self.logRecordAttributeInterceptors.append(AnyInterceptor(interceptor))
    return self
  }

  @_disfavoredOverload
  @available(iOS 16, *)
  public func addLogRecordAttributeInterceptor(_ interceptor: any Interceptor<[String: AttributeValue]>) -> Self {
    return addLogRecordAttributeInterceptor(AnyInterceptor(interceptor))
  }

  public func addResourceInterceptor(_ interceptor: some Interceptor<Resource>) -> Self {
    self.resourceInterceptors.append(AnyInterceptor(interceptor))
    return self
  }

  @_disfavoredOverload
  @available(iOS 16, *)
  public func addResourceInterceptor(_ interceptor: any Interceptor<Resource>) -> Self {
    return addResourceInterceptor(AnyInterceptor(interceptor))
  }

  public func build() -> AgentConfiguration {

    var config = AgentConfiguration()
    config.sampleRate = sampleRate
    config.logFilters = logFilters
    config.spanFilters = spanFilters
    config.connectionType = connectionType
    config.managementUrl = self.managementUrl
    if let enableRemoteManagement {
      config.remoteManagementEnabled = enableRemoteManagement
    }
    config.useLegacyAttributeNames = legacyAttributeNames

    if let interceptor = Self.combine(spanAttributeInterceptors) {
      config.spanAttributeInterceptor = interceptor
    }
    if let interceptor = Self.combine(logRecordAttributeInterceptors) {
      config.logRecordAttributeInterceptor = interceptor
    }
    config.resourceInterceptors = resourceInterceptors

    let endpointUrl = self.exportUrl ?? self.serverUrl
    config.setFullExportUrl(endpointUrl)
    if let endpointUrl {
      config.projectFullExportUrl(endpointUrl)
    }

    if let auth = self.auth {
      config.auth = auth
    }
    if let enableAgent = self.enableAgent {
      config.enableAgent = enableAgent
    }
    config.enableOpAMP = enableOpAPM
    return config
  }

  /// Returns `nil` when no interceptor was added, the single interceptor
  /// itself, or a `MultiInterceptor` that runs them in the order they were added.
  private static func combine<Item>(
    _ interceptors: [AnyInterceptor<Item>]
  ) -> AnyInterceptor<Item>? {
    switch interceptors.count {
    case 0:
      return nil
    case 1:
      return interceptors[0]
    default:
      return AnyInterceptor(MultiInterceptor(interceptors))
    }
  }
}
