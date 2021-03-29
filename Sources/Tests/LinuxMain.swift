import XCTest

import apm_agent_iosTests

var tests = [XCTestCaseEntry]()
tests += apm_agent_iosTests.allTests()
XCTMain(tests)
