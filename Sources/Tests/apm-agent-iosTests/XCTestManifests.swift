import XCTest

#if !canImport(ObjectiveC)
    public func allTests() -> [XCTestCaseEntry] {
        return [
            testCase(apm_agent_iosTests.allTests),
        ]
    }
#endif
