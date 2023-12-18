// Copyright © 2023 Elasticsearch BV
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
import NetworkStatus

class NetworkStatusManager {
  static private var networkStatusKey = "co.elastic.network.status"
  public private(set) var lastStatus: String? {
    get {
      UserDefaults.standard.object(forKey: Self.networkStatusKey) as? String
    }
    set(value) {
      UserDefaults.standard.setValue(value, forKey: Self.networkStatusKey)
    }
  }

  private static var instance: NetworkStatus?

  private static func shared() -> NetworkStatus? {
    guard let existingInstance = instance else {
      do {
        Self.instance = try NetworkStatus()
        return Self.instance
      } catch {
        return nil
      }
    }
    return existingInstance
  }

  func status() -> String {
    guard let currentInstance = Self.shared() else {
      return "unavailable"
    }

    let status = currentInstance.status().0
    if status != lastStatus {
      lastStatus = status
    }
    return status
  }
}
