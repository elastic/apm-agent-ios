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

/// A type-erased `Interceptor`.
///
/// Stores any interceptor of a given `Item` type without a constrained
/// existential (`any Interceptor<Item>`), which needs iOS 16 at runtime.
public struct AnyInterceptor<Item>: Interceptor {
  /// The wrapped interceptor, never itself an `AnyInterceptor`.
  let base: Any
  private let interceptItem: (Item) -> Item

  public init<I: Interceptor>(_ base: I) where I.Item == Item {
    if let erased = base as? AnyInterceptor<Item> {
      self = erased
      return
    }
    self.base = base
    self.interceptItem = base.intercept
  }

  public func intercept(_ item: Item) -> Item {
    return interceptItem(item)
  }
}
