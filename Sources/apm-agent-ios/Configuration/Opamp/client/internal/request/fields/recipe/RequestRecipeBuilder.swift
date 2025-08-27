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

public extension RequestRecipe {
   class Builder {
    private var fields: Set<FieldType>
    private let manager: RecipeManager
     internal init(manager: RecipeManager){
       self.manager = manager
       self.fields = Set<FieldType>(self.manager.constFields)
     }
    @discardableResult
    public func addField(_ field: FieldType) -> Self {
      fields.insert(field)
      return self
    }
    @discardableResult
    func addAllFields(_ fields: [FieldType]) -> Self {
      for field in fields {
        self.fields.insert(field)
      }
      return self
    }
    @discardableResult
    func merge(with other: RequestRecipe) -> Self {
      return addAllFields(other.fields)
    }

    func build() -> RequestRecipe {
      let requestRecipt = RequestRecipe(fields: Array(fields))
      self.manager.setPrevious(recipe: requestRecipt)
      return requestRecipt
    }
  }
}
