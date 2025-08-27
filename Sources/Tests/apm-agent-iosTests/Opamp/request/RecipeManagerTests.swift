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


import Foundation
import XCTest
@testable import ElasticApm

public class OpampRecipeManagerTests : XCTestCase {
  func testRecipeManager() {
    let recipeManager = RecipeManager()
    XCTAssertNil(
      recipeManager.previous(),
      "There should be no previous recipe after initialization"
    )

    let newRecipeBuilder = recipeManager
      .next()
      .addAllFields([.AGENT_DESCRIPTION,.AGENT_DISCONNECT])

    let newRecipe = newRecipeBuilder.build()
    XCTAssertEqual(recipeManager.previous()?.fields, newRecipe.fields, "after a new recipe is built, it become previous")

    XCTAssertFalse(newRecipeBuilder === recipeManager.next(), "New builder in next() after last was built.")

    let recipeBuilder = recipeManager.next().addField(.INSTANCE_UID)
    XCTAssertTrue(
      recipeBuilder === recipeManager.next(),
      "only one builder at a time."
    )
  }

  func testUseOldRecipeToBuild() {
    let recipeManager = RecipeManager()
    let recipe = recipeManager.next().addAllFields(
      [.AGENT_DESCRIPTION, .EFFECTIVE_CONFIG]
    ).build()
    let nextRecipe = recipeManager.next().merge(with: recipe).addField(.AGENT_DISCONNECT).build()

    XCTAssertEqual(
      nextRecipe.fields.sorted(),
      [.AGENT_DESCRIPTION, .AGENT_DISCONNECT, .EFFECTIVE_CONFIG]
    )
  }

  func testInitialFields() {
    let constFields: [FieldType] = [
      .AGENT_DESCRIPTION,
      .CAPABILITIES,
      .EFFECTIVE_CONFIG
    ]
    let recipeManager = RecipeManager(
      constFields: constFields
    )

    let recipe = recipeManager.next().build()
    XCTAssertEqual(
      constFields,
      recipe.fields.sorted(),
      "const fields should automatically be applied."
    )
  }
}
