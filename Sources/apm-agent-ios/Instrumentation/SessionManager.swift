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
    static let sessionTimeout: TimeInterval = 30 * 60
    public static var instance = SessionManager()
    private var currentId: UUID {
        get {
            UserDefaults.standard.object(forKey: Self.sessionIdKey) as? UUID ?? UUID()
        }
        set(uuid) {
            UserDefaults.standard.setValue(uuid, forKey: Self.sessionIdKey)
        }
    }

    private var lastUpdated: Date {
        get {
            UserDefaults.standard.object(forKey: Self.sessionTimerKey) as? Date ?? Date.distantPast
        }
        set(date) {
            UserDefaults.standard.setValue(date, forKey: Self.sessionTimerKey)
        }
    }

    private init() {
        if !isValid() {
            refreshSession()
        }
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
        lastUpdated.timeIntervalSinceNow < Self.sessionTimeout
    }
}
