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

/// A type-erased `OpampClientCallback`.
///
/// Stores any callback for a given `Client` type without a constrained
/// existential (`any OpampClientCallback<Client>`), which needs iOS 16 at
/// runtime.
struct AnyOpampClientCallback<Client: OpampClientInterface>: OpampClientCallback {
  private let connect: (Client) -> Void
  private let connectFailed: (Client, Error, TimeInterval) -> Void
  private let errorResponse: (Client, Error, TimeInterval) -> Void
  private let message: (Client, OpampMessage) -> Void

  init<C: OpampClientCallback>(_ base: C) where C.Client == Client {
    connect = base.onConnect
    connectFailed = base.onConnectFailed
    errorResponse = base.onErrorResponse
    message = base.onMessage
  }

  func onConnect(client: Client) {
    connect(client)
  }

  func onConnectFailed(client: Client, error: Error, retryAfter: TimeInterval) {
    connectFailed(client, error, retryAfter)
  }

  func onErrorResponse(client: Client, error: Error, retryAfter: TimeInterval) {
    errorResponse(client, error, retryAfter)
  }

  func onMessage(client: Client, message: OpampMessage) {
    self.message(client, message)
  }
}
