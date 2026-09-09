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

struct InstallationIdProvider {
  static let storageKey = "elastic.app.installation.id"
  private static let storageLock = NSLock()

  private let userDefaults: UserDefaults

  init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults
  }

  func get() -> String {
    Self.storageLock.lock()
    defer { Self.storageLock.unlock() }

    if let storedValue = userDefaults.string(forKey: Self.storageKey),
      UUID(uuidString: storedValue) != nil {
      return storedValue
    }

    let installationId = UUID().uuidString
    userDefaults.set(installationId, forKey: Self.storageKey)
    return installationId
  }
}
