// Copyright © 2022 Elasticsearch BV
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
import os


class SimpleActivityContextManager : ContextManager {
    private let logger = OSLog(subsystem: "co.elastic.simpleActivityContextManager", category: "TracingContext")
    static let instance = SimpleActivityContextManager()
    
    private let rlock = NSRecursiveLock()
    private var contextMap = [SpanId : [String: ActivityStack]]()
    private var rootToActivityMap = NSMapTable<AnyObject, Activity>(keyOptions:.weakMemory,valueOptions: .strongMemory)
    private var activityStack = [Activity]()
    
    class Activity {
        
        var id: SpanId
        init(id: SpanId) {
            self.id = id
        }
    }

    func getCurrentContextValue(forKey key: OpenTelemetryApi.OpenTelemetryContextKeys) -> AnyObject? {
        rlock.lock()
        defer {
            rlock.unlock()
        }
        if let activity = activityStack.last, let context = contextMap[activity.id] {
            os_log("instance[0x%x] has Current Activity: %s",log: logger, type: .debug,unsafeBitCast(self, to: Int.self), activity.id.hexString)
            return context[key.rawValue]?.peek()
        }
        
        os_log("instance[0x%x] has no current context.",log: logger, type: .debug,unsafeBitCast(self, to: Int.self))
        return nil
    }
    
    func setCurrentContextValue(forKey key: OpenTelemetryApi.OpenTelemetryContextKeys, value: AnyObject) {
        rlock.lock()
        defer {
            rlock.unlock()
        }
       
        if let span = value as? RecordEventsReadableSpan  {
            if contextMap[span.context.spanId] == nil || contextMap[span.context.spanId]?[key.rawValue] == nil {
                os_log("instance[0x%x] created activity: %s",log: logger, type: .debug,unsafeBitCast(self, to: Int.self), span.context.spanId.hexString)
                rootToActivityMap.setObject(Activity(id:span.context.spanId), forKey: value)
                contextMap[span.context.spanId] = [String: ActivityStack]()
                contextMap[span.context.spanId]?[key.rawValue] = ActivityStack()
            }
            contextMap[span.context.spanId]?[key.rawValue]?.push(value)
            activityStack.append(Activity(id: span.context.spanId))
          }
    }
    
    func removeContextValue(forKey key: OpenTelemetryApi.OpenTelemetryContextKeys, value: AnyObject) {
        rlock.lock()
        defer {
            rlock.unlock()
        }
        if let id = rootToActivityMap.object(forKey: value)?.id {
                self.rlock.lock()
                defer {
                    self.rlock.unlock()
                }
                if self.contextMap[id] != nil && self.contextMap[id]!.isEmpty {
                    self.contextMap.removeValue(forKey: id)
                }
                self.rootToActivityMap.removeObject(forKey: value)
                self.activityStack.removeAll { a in
                    if let v = value as? Activity {
                        return a.id.hexString == v.id.hexString
                    }
                    return false
                }
            
        } else {
            if let span = value as? RecordEventsReadableSpan    {
                if var stack = contextMap[span.context.spanId]?[key.rawValue] {
                    stack.remove(value)
                    self.activityStack.removeAll { a in
                        if let v = value as? Activity {
                            return a.id.hexString == v.id.hexString
                        }
                        return false
                    }
                }
            }
        }
    }
    

}
