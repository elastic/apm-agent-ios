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
import OpenTelemetrySdk
import PersistenceExporter

public class AgentConfigBuilder {
  private var enableAgent: Bool?
  private var url: URL?
  private var exportUrl: URL?
  private var managementUrl: URL?
  private var enableRemoteManagement: Bool = true
  private var auth: String?
  private static let bearer = "Bearer"
  private static let api = "ApiKey"
  private var connectionType : AgentConnectionType = .grpc
  private var sampleRate = 1.0

  private var spanFilters = [SignalFilter<ReadableSpan>]()
  private var logFilters = [SignalFilter<MutableLogRecord>]()
  private var metricFilters = [SignalFilter<Metric>]()

  public init() {}

  public func disableAgent() -> Self {
    enableAgent = false
    return self
  }

  @available(*, deprecated, renamed: "withExportUrl", message: "Export and config management URLs will be seperated in future.")
  public func withServerUrl(_ url: URL) -> Self {
    self.url = url
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

  public func withApiKey(_ key: String) -> Self {
    self.auth = "\(Self.api) \(key)"
    return self
  }

  public func withSessionSampleRate(_ rate: Double) -> Self {
    sampleRate = min(max(rate, 0.0), 1.0)
    return self
  }

  public func addSpanFilter(_ shouldInclude: @escaping (inout any ReadableSpan) -> Bool) -> Self {
    spanFilters.append(SignalFilter<ReadableSpan>(shouldInclude))
    return self
  }
  public func addMetricFilter(_ shouldInclude: @escaping (inout Metric) -> Bool) -> Self {
    metricFilters.append(SignalFilter<Metric>(shouldInclude))
    return self
  }

  public func addLogFilter(_ shouldInclude: @escaping (inout MutableLogRecord) -> Bool) -> Self {
    logFilters.append(SignalFilter<MutableLogRecord>(shouldInclude))
    return self
  }

  public func build() -> AgentConfiguration {

    var config = AgentConfiguration()
    config.sampleRate = sampleRate
    config.logFilters = logFilters
    config.spanFilters = spanFilters
    config.metricFilters = metricFilters
    config.connectionType = connectionType
    config.managementUrl = self.managementUrl
    config.enableRemoteManagement = enableRemoteManagement

    let url = self.exportUrl ?? self.url
    if let url {
      if let proto = url.scheme, proto == "https" {
        config.collectorTLS = true
      }
      if let host = url.host {
        config.collectorHost = host
      }
      if let port = url.port {
        config.collectorPort = port
      }
      if let auth = self.auth {
        config.auth = auth
      }
    }

    if let enableAgent = enableAgent {
      config.enableAgent = enableAgent
    }
    return config
  }
}
