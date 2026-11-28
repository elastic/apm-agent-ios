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

/// Unchecked `Sendable` is safe because this type is immutable; the setter documents that the
/// application's interceptor must be thread-safe.
final class ExportHeadersProvider: @unchecked Sendable {
  private let auth: String?
  private let interceptor: AnyInterceptor<[String: String]>?

  init(_ configuration: AgentConfiguration) {
    auth = configuration.auth
    interceptor = configuration.exportHeadersInterceptor
  }

  var configuration: OtlpConfiguration {
    // Pass all headers through the provider: upstream merges static headers back in, which
    // would restore any header the interceptor removes.
    OtlpConfiguration(headersProvider: { [self] in
      let generated = Dictionary(
        uniqueKeysWithValues: OpenTelemetryHelper.generateExporterHeaders(auth) ?? [])
      return Array((interceptor?.intercept(generated) ?? generated))
    })
  }
}
