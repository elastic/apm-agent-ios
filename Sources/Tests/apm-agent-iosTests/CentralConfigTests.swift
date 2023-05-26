// Copyright © 2023 Elasticsearch BV
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

import XCTest

@testable import iOSAgent

class CentralConfigTests: XCTestCase {
  let nullJson = """
    {}
    """
  let withRecording = """
    {
        "recording": "true",
        "sampleRate": 1.0
    }
    """
  let withoutRecording = """
    {
        "recording": "false",
        "sampleRate": 0.5
    }
    """

  let withNewFields = """
    {
        "recording" : "false",
        "new" : "new",
      "sampleRate" : 0.0
    }
    """

  let newWithNoRecording = """
    {
        "new" : "new"
    }
    """

  override class func setUp() {
    UserDefaults.standard.removeObject(forKey: CentralConfig.CentralConfigKey)
  }
  override func tearDown() {
    UserDefaults.standard.removeObject(forKey: CentralConfig.CentralConfigKey)
  }

  func testAgentConfigManager() {

    let c = CentralConfig()

    XCTAssertTrue(c.data.recording)

    c.config = nullJson

    XCTAssertTrue(c.data.recording)
    XCTAssertEqual(c.data.sampleRate, 1.0)

    c.config = withoutRecording

    XCTAssertFalse(c.data.recording)
    XCTAssertEqual(c.data.sampleRate, 0.5)

    c.config = nullJson

    XCTAssertTrue(c.data.recording)
    XCTAssertEqual(c.data.sampleRate, 1.0)

    c.config = withNewFields

    XCTAssertFalse(c.data.recording)
    XCTAssertEqual(c.data.sampleRate, 0.0)

    c.config = newWithNoRecording

    // should fall back to true
    XCTAssertTrue(c.data.recording)
  }

  func testMultiObjects() {
    let one = CentralConfig()
    let two = CentralConfig()

    XCTAssertTrue(one.data.recording)
    XCTAssertTrue(two.data.recording)

    one.config = withoutRecording

    XCTAssertFalse(one.data.recording)
    XCTAssertFalse(two.data.recording)

    let three = CentralConfig()

    XCTAssertFalse(three.data.recording)
  }

  func testMaxAgeParse() {
    let cacheControl = "max-age=30, must-revalidate"
    let result = CentralConfigFetcher.parseMaxAge(cacheControl: cacheControl)
    XCTAssertEqual(result, 30.0)
  }
}
