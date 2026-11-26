// Copyright © 2026 Elasticsearch BV
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

import OpenTelemetryProtocolExporterCommon

/// Resolves application headers for OTLP only. Management requests retain their existing
/// `OpenTelemetryHelper.generateExporterHeaders` and legacy-poll authentication paths.
///
/// The public Interceptor protocol predates Sendable. This narrow adapter is immutable after
/// initialization: it owns a copied auth value and a fixed type-erased callback, and each call
/// creates its own map. No SDK state is mutated or lock held while user code runs. As documented
/// on the setter, the application must make the interceptor and its captures safe for overlapping
/// calls. The unchecked conformance bridges that explicit callback contract without changing
/// the concurrency requirements of unrelated public interceptors.
final class ExportHeadersProvider: @unchecked Sendable {
  private let auth: String?
  private let interceptor: AnyInterceptor<[String: String]>?

  init(_ configuration: AgentConfiguration) {
    auth = configuration.auth
    interceptor = configuration.exportHeadersInterceptor
  }

  var configuration: OtlpConfiguration {
    // Keep all application headers in the provider. Static headers would be merged back by
    // upstream when an interceptor intentionally removes authorization or returns an empty map.
    OtlpConfiguration(headersProvider: { [self] in
      let generated = Dictionary(
        uniqueKeysWithValues: OpenTelemetryHelper.generateExporterHeaders(auth) ?? [])
      return Array((interceptor?.intercept(generated) ?? generated))
    })
  }
}
