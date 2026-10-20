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

public struct MultiInterceptor<T>: Interceptor {
  var interceptors: [AnyInterceptor<T>] = []

  /// Runs `interceptors` in the given order. A nested `MultiInterceptor` is
  /// flattened at its position, and `NoopInterceptor`s are dropped.
  public init(_ interceptors: [AnyInterceptor<T>]) {
    for interceptor in interceptors {
      if let multiInterceptor = interceptor.base as? MultiInterceptor<T> {
        self.interceptors.append(contentsOf: multiInterceptor.interceptors)
      } else if !(interceptor.base is NoopInterceptor<T>) {
        self.interceptors.append(interceptor)
      }
    }
  }

  @_disfavoredOverload
  @available(iOS 16, *)
  public init(_ interceptors: [any Interceptor<T>]) {
    self.init(interceptors.map { AnyInterceptor($0) })
  }

  public func intercept(_ item: T) -> T {
    var result: T = item
    interceptors.forEach {
      result = $0.intercept(result)
    }
    return result
  }
}
