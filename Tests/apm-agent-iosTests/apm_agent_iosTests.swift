import XCTest
@testable import ElasticAgent

final class apm_agent_iosTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
//        XCTAssertEqual(apm_agent_ios().text, "Hello, World!")
        agent.init()
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
