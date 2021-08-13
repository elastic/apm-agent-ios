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
import UIKit


extension UIViewController {
    static var key : UInt8 = 0
    func setInstrumentationName(name: String) -> Self {
        objc_setAssociatedObject(self, &Self.key, name, .OBJC_ASSOCIATION_RETAIN)
        return self
    }
    
    func instrumentationName() -> String? {
        return objc_getAssociatedObject(self, &Self.key) as? String  ?? nil 
    }
}
