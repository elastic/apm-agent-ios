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

@testable import iOSAgent
import XCTest

final class SessionManagerTests: XCTestCase {
    func testInvalidSession() {
        _ = SessionManager.instance
        UserDefaults.standard.setValue("0.0", forKey: SessionManager.sessionIdKey)

        UserDefaults.standard.setValue(Date.distantPast, forKey: SessionManager.sessionTimerKey)

        XCTAssertFalse(SessionManager.instance.isValid())
    }

    func testAutoSessionUpdate() {
        _ = SessionManager.instance
        let uuid = UUID()
        UserDefaults.standard.setValue(uuid.uuidString, forKey: SessionManager.sessionIdKey)

        UserDefaults.standard.setValue(Date.distantPast, forKey: SessionManager.sessionTimerKey)

        XCTAssertTrue(SessionManager.instance.session() != uuid.uuidString)

        XCTAssertTrue(SessionManager.instance.isValid())
    }
    
    func testMaxSessionLength() {
        _ = SessionManager.instance
        let uuid = UUID()
        UserDefaults.standard.setValue(uuid.uuidString, forKey: SessionManager.sessionIdKey)

        UserDefaults.standard.setValue(Date().timeIntervalSince1970, forKey: SessionManager.sessionTimerKey)
        
        UserDefaults.standard.setValue(Date().timeIntervalSince1970, forKey: SessionManager.sessionStartKey)
        
        XCTAssertTrue(SessionManager.instance.session() == uuid.uuidString)

        XCTAssertTrue(SessionManager.instance.isValid())
        
        // Set 4 hours ago session start
        UserDefaults.standard.setValue(Date(timeInterval: -SessionManager.sessionMax, since: Date()).timeIntervalSince1970, forKey: SessionManager.sessionStartKey)

        XCTAssertFalse(SessionManager.instance.isValid())
        
        
        XCTAssertTrue(SessionManager.instance.session() != uuid.uuidString)

        XCTAssertTrue(SessionManager.instance.isValid())

    
    }
}
