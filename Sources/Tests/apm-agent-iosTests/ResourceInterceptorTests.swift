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
import OpenTelemetryApi
import OpenTelemetrySdk
import OSLog
import XCTest

@testable import ElasticApm

final class ResourceInterceptorTests: XCTestCase {
  private let emptyEnvironment = AgentEnvResource.get([:])

  func testBuilderWithoutResourceInterceptorKeepsTheNoopDefault() {
    let configuration = AgentConfigBuilder().build()

    XCTAssertTrue(configuration.resourceInterceptor is NoopInterceptor<Resource>)
  }

  func testBuilderInstallsASingleResourceInterceptor() {
    let configuration = AgentConfigBuilder()
      .addResourceInterceptor(setting("custom.single", to: "set"))
      .build()

    let resource = configuration.resourceInterceptor.intercept(Resource(attributes: [:]))

    XCTAssertEqual(resource.attributes, ["custom.single": .string("set")])
  }

  func testResourceInterceptorsRunInTheOrderTheyWereAdded() {
    let first = ClosureInterceptor<Resource> { resource in
      resource.merging(other: Resource(attributes: ["custom.order": .string("first")]))
    }
    let second = ClosureInterceptor<Resource> { resource in
      guard case let .string(previous) = resource.attributes["custom.order"] else {
        return resource
      }
      return resource.merging(
        other: Resource(attributes: ["custom.order": .string("\(previous),second")]))
    }
    let configuration = AgentConfigBuilder()
      .addResourceInterceptor(first)
      .addResourceInterceptor(second)
      .build()

    let resource = AgentResource.get(
      configuration: configuration,
      environmentResource: emptyEnvironment)

    XCTAssertEqual(resource.attributes["custom.order"], .string("first,second"))
  }

  func testANestedInterceptorGroupRunsAtThePositionItWasAdded() {
    let configuration = AgentConfigBuilder()
      .addResourceInterceptor(appendingOrder("a"))
      .addResourceInterceptor(
        MultiInterceptor<Resource>([appendingOrder("b"), appendingOrder("c")]))
      .build()

    let resource = AgentResource.get(
      configuration: configuration,
      environmentResource: emptyEnvironment)

    XCTAssertEqual(resource.attributes["custom.order"], .string("a,b,c"))
    let detected = AgentResource.get(
      configuration: AgentConfigBuilder().build(),
      environmentResource: emptyEnvironment)
    XCTAssertEqual(
      resource.attributes,
      detected.attributes.merging(["custom.order": .string("a,b,c")]) { _, new in new })
  }

  func testInterceptorValueOverridesOtelResourceAttributes() {
    let environment = AgentEnvResource.get([
      AgentEnvResource.otelResourceAttributesEnv: "custom.precedence=env"
    ])
    let configuration = AgentConfigBuilder()
      .addResourceInterceptor(setting("custom.precedence", to: "api"))
      .build()

    let resource = AgentResource.get(
      configuration: configuration,
      environmentResource: environment)

    XCTAssertEqual(resource.attributes["custom.precedence"], .string("api"))
  }

  func testOtelResourceAttributesValueSurvivesWithoutAnInterceptorForTheKey() {
    let environment = AgentEnvResource.get([
      AgentEnvResource.otelResourceAttributesEnv: "custom.precedence=env"
    ])

    let withoutInterceptor = AgentResource.get(
      configuration: AgentConfigBuilder().build(),
      environmentResource: environment)
    let withUnrelatedInterceptor = AgentResource.get(
      configuration: AgentConfigBuilder()
        .addResourceInterceptor(setting("custom.other", to: "api"))
        .build(),
      environmentResource: environment)

    XCTAssertEqual(withoutInterceptor.attributes["custom.precedence"], .string("env"))
    XCTAssertEqual(withUnrelatedInterceptor.attributes["custom.precedence"], .string("env"))
  }

  func testInterceptorCanRemoveADetectedAttribute() {
    let installationId = SemanticConventions.App.installationId.rawValue
    let detected = AgentResource.get(
      configuration: AgentConfigBuilder().build(),
      environmentResource: emptyEnvironment)
    XCTAssertNotNil(detected.attributes[installationId])

    let configuration = AgentConfigBuilder()
      .addResourceInterceptor(
        ClosureInterceptor<Resource> { resource in
          var attributes = resource.attributes
          attributes.removeValue(forKey: installationId)
          return Resource(attributes: attributes)
        }
      )
      .build()

    let resource = AgentResource.get(
      configuration: configuration,
      environmentResource: emptyEnvironment)

    XCTAssertNil(resource.attributes[installationId])
    var expected = detected.attributes
    expected.removeValue(forKey: installationId)
    XCTAssertEqual(resource.attributes, expected)
  }

  func testInterceptorOutputWithoutAttributesKeepsTheInputAndLogsOneError() throws {
    let detected = AgentResource.get(
      configuration: AgentConfigBuilder().build(),
      environmentResource: emptyEnvironment)
    let configuration = AgentConfigBuilder()
      .addResourceInterceptor(addingInvalidKey())
      .build()
    let errorsBefore = try emptyInterceptedResourceErrorCount()

    let resource = AgentResource.get(
      configuration: configuration,
      environmentResource: emptyEnvironment)

    XCTAssertEqual(resource, detected)
    XCTAssertNil(resource.attributes["custom.valid"])
    XCTAssertEqual(try emptyInterceptedResourceErrorCount() - errorsBefore, 1)
  }

  func testInterceptorOutputWithAttributesLogsNoError() throws {
    let configuration = AgentConfigBuilder()
      .addResourceInterceptor(setting("custom.valid", to: "kept"))
      .build()
    let errorsBefore = try emptyInterceptedResourceErrorCount()

    let resource = AgentResource.get(
      configuration: configuration,
      environmentResource: emptyEnvironment)

    XCTAssertEqual(resource.attributes["custom.valid"], .string("kept"))
    XCTAssertEqual(try emptyInterceptedResourceErrorCount() - errorsBefore, 0)
  }

  /// Counts this process's fallback errors so far.
  private func emptyInterceptedResourceErrorCount() throws -> Int {
    try OSLogStore(scope: .currentProcessIdentifier).getEntries(
      matching: NSPredicate(
        format: "subsystem == %@ AND category == %@", "co.elastic.ElasticApm", "Resource")
    )
    .compactMap { $0 as? OSLogEntryLog }
    .filter {
      $0.level == .error
        && $0.composedMessage == AgentResource.emptyInterceptedResourceMessage
    }
    .count
  }

  /// Appends `name` to the comma-separated `custom.order` attribute.
  private func appendingOrder(_ name: String) -> ClosureInterceptor<Resource> {
    ClosureInterceptor<Resource> { resource in
      var order = name
      if case let .string(previous) = resource.attributes["custom.order"] {
        order = "\(previous),\(name)"
      }
      return resource.merging(other: Resource(attributes: ["custom.order": .string(order)]))
    }
  }

  private func setting(_ key: String, to value: String) -> ClosureInterceptor<Resource> {
    ClosureInterceptor<Resource> { resource in
      resource.merging(other: Resource(attributes: [key: .string(value)]))
    }
  }
}

/// Adds a valid key and a key with a non-ASCII character by building a new
/// `Resource`, whose initializer then keeps no attributes at all.
func addingInvalidKey() -> ClosureInterceptor<Resource> {
  ClosureInterceptor<Resource> { resource in
    var attributes = resource.attributes
    attributes["custom.valid"] = .string("value")
    attributes["custom.caf\u{E9}"] = .string("value")
    return Resource(attributes: attributes)
  }
}
