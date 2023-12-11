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

enum SwizzleError: Error {
    case targetNotFound(class: String, method: String)
}

internal class MethodSwizzler<T, U>: Instrumentor {
    typealias IMPSignature = T
    typealias BlockSignature = U
    let selector: Selector
    let klass: AnyClass
    let target: Method

    required internal init(selector: Selector, klass: AnyClass) throws {
        self.selector = selector
        self.klass = klass
         guard let method = class_getInstanceMethod(klass, selector) else {
            throw SwizzleError.targetNotFound(class: NSStringFromClass(klass), method: NSStringFromSelector(selector))
        }
        target = method
    }

    func swap(with conversion: (IMPSignature) -> BlockSignature) {
        sync {
            let implementation = method_getImplementation(target)
            let currentObjCImp = unsafeBitCast(implementation, to: IMPSignature.self)
            let newBlock: BlockSignature = conversion(currentObjCImp)
            let newIMP: IMP = imp_implementationWithBlock(newBlock)
            method_setImplementation(target, newIMP)
        }
    }

    @discardableResult
    private func sync<V>(block: () -> V) -> V {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        return block()
    }

}
