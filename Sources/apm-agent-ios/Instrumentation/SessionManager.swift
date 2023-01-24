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

import Foundation

public class SessionManager {
    static let sessionIdKey = "elastic.session.id"
    static let sessionTimerKey = "elastic.session.timer"
    static let defaultSessionTimeout: TimeInterval = 30 * 60 // 30 minutes
    static let sessionMax : TimeInterval = 4 * 60 * 60 // 4 hours
    
    private var sessionStart : Date = Date.distantPast
    private var sessionTimeout : TimeInterval = defaultSessionTimeout
    private let timeoutLock = NSLock()
    public private(set) static var instance = SessionManager()
    
    private var currentId: UUID {
        get {
            UUID(uuidString: UserDefaults.standard.object(forKey: Self.sessionIdKey) as? String ?? "") ?? UUID()
        }
        set(uuid) {
            UserDefaults.standard.setValue(uuid.uuidString, forKey: Self.sessionIdKey)
        }
    }

    private var lastUpdated: Date {
        get {
            Date(timeIntervalSince1970: UserDefaults.standard.object(forKey: Self.sessionTimerKey) as? TimeInterval ?? Date.distantPast.timeIntervalSince1970)
        }
        set(date) {
            UserDefaults.standard.setValue(date.timeIntervalSince1970, forKey: Self.sessionTimerKey)
        }
    }

    private init() {
        if !isValid() {
            refreshSession()
        }
    }

    public func setSessionTimeout(_ timeout: TimeInterval) {
        timeoutLock.lock()
        defer {
            timeoutLock.unlock()
        }
        self.sessionTimeout = timeout
    }
    
    public func session() -> String {
        if isValid() {
            updateTimeout()
        } else {
            refreshSession()
        }
        return currentId.uuidString
    }

    public func updateTimeout() {
        lastUpdated = Date()
    }

    func refreshSession() {
        currentId = UUID()
        lastUpdated = Date()
    }

    func isValid() -> Bool {
        timeoutLock.lock()
        let timeout = sessionTimeout
        timeoutLock.unlock()
        
        return lastUpdated.timeIntervalSinceNow.magnitude < timeout && Date().timeIntervalSince(sessionStart) >= Self.sessionMax
    }
}
