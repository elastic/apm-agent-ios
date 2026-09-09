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
import XCTest

@testable import ElasticApm

final class InstallationIdProviderTests: XCTestCase {
  func testConcurrentFirstReadsReturnSameInstallationId() throws {
    let suiteName = "InstallationIdProviderTests.\(UUID().uuidString)"
    let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    userDefaults.removePersistentDomain(forName: suiteName)
    defer {
      userDefaults.removePersistentDomain(forName: suiteName)
    }

    let valuesLock = NSLock()
    var values = [String]()

    DispatchQueue.concurrentPerform(iterations: 100) { _ in
      let value = InstallationIdProvider(userDefaults: userDefaults).get()
      valuesLock.lock()
      values.append(value)
      valuesLock.unlock()
    }

    let persistedValue = try XCTUnwrap(
      userDefaults.string(forKey: InstallationIdProvider.storageKey))
    XCTAssertEqual(Set(values), [persistedValue])
  }

  func testPersistsAndRegeneratesInstallationId() throws {
    let suiteName = "InstallationIdProviderTests.\(UUID().uuidString)"
    let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    userDefaults.removePersistentDomain(forName: suiteName)
    defer {
      userDefaults.removePersistentDomain(forName: suiteName)
    }

    let provider = InstallationIdProvider(userDefaults: userDefaults)
    let first = provider.get()

    XCTAssertNotNil(UUID(uuidString: first))
    XCTAssertEqual(provider.get(), first)

    userDefaults.removeObject(forKey: InstallationIdProvider.storageKey)
    let replacement = provider.get()

    XCTAssertNotNil(UUID(uuidString: replacement))
    XCTAssertNotEqual(replacement, first)

    userDefaults.set("invalid", forKey: InstallationIdProvider.storageKey)
    let repaired = provider.get()

    XCTAssertNotNil(UUID(uuidString: repaired))
    XCTAssertNotEqual(repaired, "invalid")
  }
}
