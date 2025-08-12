// Copyright © 2025 Elasticsearch BV
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

public protocol OpampClientInterface {
  associatedtype Client: OpampClientInterface
  /// Starts the OpAMP client & attempts to connect to the Server. Once a connection is established
  ///  the client will attempt to maintain it by reconnecting if the connection is lost. All failed connection
  ///  attempts will be reported via the `Callback` `onConnectFailed` callback.
  /// - Parameter callback: The callback to be invoked when the client connects, fails to connect,
  ///                        or receives a message.
  func start(_ callback: any OpampClientCallback<Client>)

  /// Stops the OpAMP client. May only be called after `start`. May only be called once.
  /// After successful return it is garanteed that no callbacks will be called.
  /// Once stopped, the client cannot be restarted.
  func stop()

  /// Sets the current remote config status which will be sent in the next agent-to-server request.
  ///  - Parameter remoteConfigStatus: the new remote config status.
  func setRemoteConfigStatus(_ remoteConfigStatus: Opamp_Proto_RemoteConfigStatus)

}

public protocol OpampClientBuilderProvider<Builder> {
     associatedtype Builder: OpampClientBuilderInterface
     static func builder() -> Builder
   }

public protocol OpampClientBuilderInterface<Client> {
  associatedtype Client: OpampClientInterface
  func build(requestService: some RequestService) -> Client;
}

public struct OpampClient : OpampClientBuilderProvider  {
  public typealias Builder = OpampClientImpl.Builder
  public static func builder() -> Builder {
    return OpampClientImpl.Builder()
  }
}
