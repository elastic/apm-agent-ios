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

/// Persists the network time anchor in `UserDefaults` under one key, together with the boot time
/// derived when it was saved.
struct NTPAnchorStore {
  struct Saved: Equatable {
    let anchor: NTPClockSynchronizer.Anchor
    /// Wall clock minus continuous clock, in nanoseconds, when the anchor was saved.
    let bootNanos: Int64
  }

  enum Loaded: Equatable {
    case absent
    case malformed
    case saved(Saved)
  }

  static let key = "elastic.ntp.anchor"
  // One version byte followed by three big-endian 64-bit fields.
  private static let version: UInt8 = 1
  private static let encodedCount = 1 + 3 * 8

  private let userDefaults: UserDefaults

  init(userDefaults: UserDefaults) {
    self.userDefaults = userDefaults
  }

  func load() -> Loaded {
    guard let value = userDefaults.object(forKey: Self.key) else {
      return .absent
    }
    guard let data = value as? Data, data.count == Self.encodedCount else {
      return .malformed
    }
    let bytes = [UInt8](data)
    guard bytes[0] == Self.version else {
      return .malformed
    }
    let field = { (index: Int) in
      bytes[(1 + index * 8)..<(9 + index * 8)].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
    }
    return .saved(
      Saved(
        anchor: NTPClockSynchronizer.Anchor(
          unixNanos: Int64(bitPattern: field(0)), continuousNanos: field(1)),
        bootNanos: Int64(bitPattern: field(2))))
  }

  func save(_ saved: Saved) {
    var data = Data([Self.version])
    for field in [
      UInt64(bitPattern: saved.anchor.unixNanos),
      saved.anchor.continuousNanos,
      UInt64(bitPattern: saved.bootNanos)
    ] {
      withUnsafeBytes(of: field.bigEndian) { data.append(contentsOf: $0) }
    }
    userDefaults.set(data, forKey: Self.key)
  }

  func remove() {
    userDefaults.removeObject(forKey: Self.key)
  }
}
