/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Client for sending requests over HTTP.
final class OpampHttpClient {
  private let url: URL
  private let session: URLSession

  convenience init(url: URL) {
    let configuration: URLSessionConfiguration = .ephemeral
    // NOTE: RUMM-610 Default behaviour of `.ephemeral` session is to cache requests.
    // To not leak requests memory (including their `.httpBody` which may be significant)
    // we explicitly opt-out from using cache. This cannot be achieved using `.requestCachePolicy`.
    configuration.urlCache = nil
    // TODO: RUMM-123 Optimize `URLSessionConfiguration` for good traffic performance
    // and move session configuration constants to `PerformancePreset`.
    self.init(session: URLSession(configuration: configuration), url: url)
  }

  init(session: URLSession, url: URL) {
    self.url = url
    self.session = session
  }

  func send(opampRequest: OpampRequest,
            completion: @escaping (Result<(OpampResponse, HTTPURLResponse), Error>) -> Void) {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.addValue("application/x-protobuf", forHTTPHeaderField: "Content-Type")
    do {
      request.httpBody = try opampRequest.agentToServer.serializedData()

      let task = session.dataTask(with: request) { data, response, error in

        completion(httpClientResult(for: (data, response, error)))
      }
      task.resume()
    } catch {
      completion(httpClientResult(for: (nil, nil, error)))
    }
  }
}

/// An error returned if `URLSession` response state is inconsistent (like no data, no response and no error).
/// The code execution in `URLSessionTransport` should never reach its initialization.
struct URLSessionTransportInconsistencyException: Error {}

/// As `URLSession` returns 3-values-tuple for request execution, this function applies consistency constraints and turns
/// it into only two possible states of `HTTPTransportResult`.
private func httpClientResult(
  for urlSessionTaskCompletion: (Data?, URLResponse?, Error?)
) -> Result<(OpampResponse, HTTPURLResponse), Error> {
  let (data, response, error) = urlSessionTaskCompletion

  if let error {
    return .failure(error)
  }

  guard let httpResponse = response as? HTTPURLResponse, let data = data else {
    return .failure(URLSessionTransportInconsistencyException())
  }


  do {
    return .success((OpampResponse(serverToAgent: try Opamp_Proto_ServerToAgent(serializedBytes: data)),
                     httpResponse))
  } catch {
    return .failure(error)
  }

}
