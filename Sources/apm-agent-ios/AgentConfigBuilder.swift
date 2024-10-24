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
  var enableAgent: Bool?
  var url: URL?
  var auth: String?
  static let bearer = "Bearer"
  static let api = "ApiKey"
  var connectionType : AgentConnectionType = .grpc
  var sampleRate = 1.0

  var spanFilters = [SignalFilter<ReadableSpan>]()
  var logFilters = [SignalFilter<ReadableLogRecord>]()
  var metricFilters = [SignalFilter<Metric>]()

  public init() {}

  public func disableAgent() -> Self {
    enableAgent = false
    return self
  }
  public func withServerUrl(_ url: URL) -> Self {
    self.url = url
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

  public func addSpanFilter(_ shouldInclude: @escaping (ReadableSpan) -> Bool) -> Self {
    spanFilters.append(SignalFilter<ReadableSpan>(shouldInclude))
    return self
  }
  public func addMetricFilter(_ shouldInclude: @escaping (Metric) -> Bool) -> Self {
    metricFilters.append(SignalFilter<Metric>(shouldInclude))
    return self
  }

  public func addLogFilter(_ shouldInclude: @escaping (ReadableLogRecord) -> Bool) -> Self {
    logFilters.append(SignalFilter<ReadableLogRecord>(shouldInclude))
    return self
  }

  public func build() -> AgentConfiguration {

    var config = AgentConfiguration()
    config.sampleRate = sampleRate
    config.logFilters = logFilters
    config.spanFilters = spanFilters
    config.metricFilters = metricFilters
    config.connectionType = connectionType

    if let url = url {
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
