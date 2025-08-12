//
//  Copyright © 2025  Elasticsearch BV
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

public protocol OpampClientCallback<Client> {
  associatedtype Client: OpampClientInterface
  /// Called when the connection to the Sever is successfully established. May be called after
  /// `OpampClient.start(callback _:)` is called & every time a connection is established to
  ///  the Server. For HTTP clients this is called for any request if the resonse status is *OK*. '
  ///  - Parameter client: the relevant `OpampClient`
  func onConnect(client: Client);

  /// Called when the conenction to the Server cannot be established. May bre called after
  /// `OpampClient.start(callback _:)` is called and tries to connect to the Server.
  ///  May also be called if the connection is lost and reconnection atempt fails.
  /// - Parameters:
  ///  - client: the relevant `OpampClient`
  ///  - error: The connection error
  ///  - retryAfter: The `TimeInterval` afterwhich a retry will be attempted.
  func onConnectFailed(client: Client, error: Error, retryAfter: TimeInterval);

  /// Called when the Server reports an error in response to some previously sent request. Useful for
  /// logging purposes. The Agent should not attempt to process the error by reconnecting or retrying
  /// previous operations. The client handles the error response `UNAVAILABLE` case internally by
  /// performing retries as necessary.
  /// - Parameters:
  ///  - client: the relevant `OpampClient`
  ///  - error: The response error
  ///  - retryAfter: the `TimeInterval` afterwhich the retry is attempted.
  func onErrorResponse(client: Client, error: Error, retryAfter: TimeInterval);

  /// Called when the Agent receives a message that needs to be processed. See `OpampMessage`
  /// definition for the data that may be available for processing. During `OnMessage` execution the
  /// `OpampClient` functions that change the status of the client may be called, e.g.: if RemoteConfig
  /// is processed then `OpampClient.setRemoteConfigStatus()` should be called to reflect the
  /// processing result. These functions may also be called after `onMessage` returns. This is advisable
  /// if processing can take a long time. In that case returning quickly is preferable to to avoid blocking
  /// the `OpampClient`.
  /// - Parameters:
  ///  - client: The relevant `OpampClient`
  ///  - message: The server response data that needs processing.
  func onMessage(client: Client, message: OpampMessage);
}
