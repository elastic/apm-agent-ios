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

public class RecipeManager {
  private let recipeLock = NSRecursiveLock()
  internal let constFields: [FieldType]
  private var previousRecipe: RequestRecipe? = nil
  private var recipeBuilder: RequestRecipe.Builder! = nil

  internal init(constFields: [FieldType] = []) {
    self.constFields = constFields
    self.recipeBuilder = RequestRecipe.Builder(manager: self)
  }

  public func previous() -> RequestRecipe? {
    recipeLock.lock()
    defer { recipeLock.unlock() }
    return previousRecipe
  }
  internal func setPrevious(recipe: RequestRecipe) {
    recipeLock.lock()
    defer { recipeLock.unlock() }
    previousRecipe = recipe
    recipeBuilder = RequestRecipe.Builder(manager: self)
  }
  public func next() -> RequestRecipe.Builder {
    recipeLock.lock()
    defer { recipeLock.unlock() }
    return recipeBuilder

  }
}
