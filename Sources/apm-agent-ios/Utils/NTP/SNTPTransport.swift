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

import Foundation

/// The longest one SNTP attempt may take. The transport applies it to the whole exchange, and
/// the clock owner rejects a reply that arrives later than this after the request was sent.
enum SNTPAttempt {
  static let deadline: TimeInterval = 5
}

/// Sends one SNTP request and reports exactly one result.
protocol SNTPTransport: AnyObject {
  /// Calls `makeRequest` immediately before sending, so the request carries the send time.
  func exchange(
    _ makeRequest: @escaping () -> Data,
    completion: @escaping (Result<Data, SNTPFailure>) -> Void)
}

// Ordinary watchOS apps cannot use low-level UDP networking (Apple TN3135), so watchOS keeps the
// system clock and has no SNTP transport.
#if !os(watchOS)
import Network

/// SNTP over one `Network.framework` UDP exchange. The deadline covers name resolution,
/// connection setup, and the reply.
final class SNTPUDPTransport: SNTPTransport {
  private let host: NWEndpoint.Host
  private let port: NWEndpoint.Port
  private let deadline: TimeInterval

  init(
    host: String = "time.apple.com",
    port: UInt16 = 123,
    deadline: TimeInterval = SNTPAttempt.deadline
  ) {
    self.host = NWEndpoint.Host(host)
    self.port = NWEndpoint.Port(rawValue: port) ?? 123
    self.deadline = deadline
  }

  func exchange(
    _ makeRequest: @escaping () -> Data,
    completion: @escaping (Result<Data, SNTPFailure>) -> Void
  ) {
    start(makeRequest, completion: completion)
  }

  @discardableResult
  func start(
    _ makeRequest: @escaping () -> Data,
    completion: @escaping (Result<Data, SNTPFailure>) -> Void
  ) -> Exchange {
    let exchange = Exchange(
      connection: NWConnection(host: host, port: port, using: .udp),
      completion: completion)
    exchange.start(makeRequest, deadline: deadline)
    return exchange
  }

  /// One in-flight request. It completes once; later replies and errors are ignored.
  final class Exchange {
    let connection: NWConnection
    private let queue = DispatchQueue(label: "co.elastic.ElasticApm.SNTPExchange")
    // Accessed only on `queue`; `nil` once the exchange has finished.
    private var completion: ((Result<Data, SNTPFailure>) -> Void)?

    fileprivate init(
      connection: NWConnection,
      completion: @escaping (Result<Data, SNTPFailure>) -> Void
    ) {
      self.connection = connection
      self.completion = completion
    }

    func cancel() {
      queue.async { self.finish(.failure(.cancelled)) }
    }

    fileprivate func start(_ makeRequest: @escaping () -> Data, deadline: TimeInterval) {
      connection.stateUpdateHandler = { [self] state in
        switch state {
        case .ready:
          send(makeRequest())
        case .failed, .waiting:
          finish(.failure(.connectionFailed))
        default:
          break
        }
      }
      queue.asyncAfter(deadline: .now() + deadline) { [weak self] in
        self?.finish(.failure(.timeout))
      }
      connection.start(queue: queue)
    }

    private func send(_ request: Data) {
      connection.send(
        content: request,
        completion: .contentProcessed { [self] error in
          if error != nil {
            finish(.failure(.connectionFailed))
          }
        })
      connection.receiveMessage { [self] data, _, _, error in
        if error == nil, let data {
          finish(.success(data))
        } else {
          finish(.failure(.connectionFailed))
        }
      }
    }

    private func finish(_ result: Result<Data, SNTPFailure>) {
      guard let completion else {
        return
      }
      self.completion = nil
      connection.stateUpdateHandler = nil
      connection.cancel()
      completion(result)
    }
  }
}
#endif
