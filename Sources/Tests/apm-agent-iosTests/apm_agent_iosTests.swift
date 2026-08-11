@testable import ElasticApm
import XCTest

final class apm_agent_iosTests: XCTestCase {
  func testEnabledInvalidConfigurationDoesNotInitializeTheAgent() {
    let configuration = AgentConfigBuilder()
      .withExportUrl(URL(string: "ftp://collector.example.com")!)
      .build()

    ElasticApmAgent.start(with: configuration)

    XCTAssertNil(ElasticApmAgent.shared())
  }

  func testDisabledConfigurationReturnsBeforeEndpointValidation() {
    let configuration = AgentConfigBuilder().disableAgent().build()

    ElasticApmAgent.start(with: configuration)

    XCTAssertNil(ElasticApmAgent.shared())
  }

  func testDeprecatedNoArgumentStartDoesNotInitializeTheAgent() {
    ElasticApmAgent.start()

    XCTAssertNil(ElasticApmAgent.shared())
  }
}
