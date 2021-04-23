// Copyright © 2021 Elasticsearch BV
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
import Reachability

public class NetworkMonitor : INetworkMonitor {
    public private(set) var reachability :Reachability
    
    public init() throws {
        reachability = try Reachability()
        try reachability.startNotifier()
    }

    deinit {
        reachability.stopNotifier()
    }
    
    public func getConnection() -> Connection {
        switch reachability.connection {
        case .wifi:
            return .wifi
        case .cellular:
            return .cellular
        case .unavailable:
            return .unavailable
        }
    }
    
    
}
