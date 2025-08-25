/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Client for sending requests over HTTP.
final class OpampHttpSender: OpampSender {
  private let url: URL
  private let session: URLSession
  private let headers: [(String, String)]?
  convenience init(url: URL, headers: [(String, String)]? = nil) {
    let configuration: URLSessionConfiguration = .ephemeral
    // NOTE: RUMM-610 Default behaviour of `.ephemeral` session is to cache requests.
    // To not leak requests memory (including their `.httpBody` which may be significant)
    // we explicitly opt-out from using cache. This cannot be achieved using `.requestCachePolicy`.
    configuration.urlCache = nil
    // TODO: RUMM-123 Optimize `URLSessionConfiguration` for good traffic performance
    // and move session configuration constants to `PerformancePreset`.
    self.init(
      session: URLSession(configuration: configuration),
      url: url,
      headers: headers
    )
  }

  init(session: URLSession, url: URL, headers: [(String,String)]?) {
    self.url = url
    self.session = session
    self.headers = headers
  }

  func send(opampRequest: OpampRequest,
            completion: @escaping (Result<(OpampResponse, URLResponse), Error>) -> Void) {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.addValue("application/x-protobuf", forHTTPHeaderField: "Content-Type")
    do {
      print("\(try opampRequest.agentToServer.jsonString())")
      request.httpBody = try opampRequest.agentToServer.serializedData()
      if let headers = headers {
        for (field, value) in headers {
          request.setValue(value, forHTTPHeaderField: field)
        }
      }
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
) -> Result<(OpampResponse, URLResponse), Error> {
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
