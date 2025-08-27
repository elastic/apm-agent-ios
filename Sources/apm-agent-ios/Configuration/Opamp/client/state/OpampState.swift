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

public class OpampState<Value: Equatable> : Supplier, @unchecked Sendable, Equatable {
  private var _value: Value
  private let rwlock: UnsafeMutablePointer<pthread_rwlock_t> = UnsafeMutablePointer.allocate(capacity: 1)

  public func get() -> Value {
    return value
  }

  public var value : Value {
    get {
      let err = pthread_rwlock_rdlock(rwlock)
      precondition(err == 0, "pthread_rwlock_wrlock failed with error \(err)")
      defer {
        let err = pthread_rwlock_unlock(rwlock)
        precondition(err == 0, "pthread_rwlock_wrlock failed with error \(err)")
      }
       return self._value
    }
    _modify {
      let err = pthread_rwlock_wrlock(rwlock)
      precondition(err == 0, "pthread_rwlock_wrlock failed with error \(err)")
      defer {
        let err = pthread_rwlock_unlock(rwlock)
        precondition(err == 0, "pthread_rwlock_wrlock failed with error \(err)")
        self.notify()
      }
      yield &_value
    }
  }

  public init(_ value: Value) {
    let err = pthread_rwlock_init(rwlock, nil)
    precondition(err == 0, "pthread_mutex_init failed with error \(err)")
    self._value = value
  }

  public func notify() {}

  public static func ==(lhs: OpampState<Value>, rhs: Value) -> Bool {
    lhs.value == rhs
  }
  
  public static func ==(rhs: Value, lhs: OpampState<Value>) -> Bool {
    rhs == lhs.value
  }

  public static func == (lhs: OpampState<Value>, rhs: OpampState<Value>) -> Bool {
    lhs.value == rhs.value
  }

  deinit {
    let err = pthread_rwlock_destroy(self.rwlock)
    precondition(err == 0, "pthread_rwlock_destroy failed with error \(err)")
    self.rwlock.deallocate()
  }
}
