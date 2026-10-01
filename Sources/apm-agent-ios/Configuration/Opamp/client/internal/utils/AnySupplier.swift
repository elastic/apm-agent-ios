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

/// A type-erased `Supplier`.
///
/// Stores any supplier of a given `Supply` type without a constrained
/// existential (`any Supplier<Supply>`), which needs iOS 16 at runtime.
struct AnySupplier<Supply>: Supplier {
  private let getSupply: () -> Supply

  init<S: Supplier>(_ base: S) where S.Supply == Supply {
    getSupply = base.get
  }

  func get() -> Supply {
    return getSupply()
  }
}
