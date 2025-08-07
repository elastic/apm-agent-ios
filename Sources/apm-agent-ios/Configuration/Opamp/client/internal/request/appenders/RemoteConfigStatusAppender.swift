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

public struct RemoteConfigStatusAppender: AgentToServerAppender {
  private let config: any Supplier<Opamp_Proto_RemoteConfigStatus>
  public init(config: any Supplier<Opamp_Proto_RemoteConfigStatus>) {
    self.config = config
  }

  public func append(to agentToServer: inout Opamp_Proto_AgentToServer) {
    agentToServer.remoteConfigStatus = config.get()
  }
}
