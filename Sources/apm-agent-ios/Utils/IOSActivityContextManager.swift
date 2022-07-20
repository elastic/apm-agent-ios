/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import os.activity
import OpenTelemetryApi
import OpenTelemetrySdk
import os

// Bridging Obj-C variabled defined as c-macroses. See `activity.h` header.
private let OS_ACTIVITY_CURRENT = unsafeBitCast(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_os_activity_current"),
                                                to: os_activity_t.self)
@_silgen_name("_os_activity_create") private func _os_activity_create(_ dso: UnsafeRawPointer?,
                                                                      _ description: UnsafePointer<Int8>,
                                                                      _ parent: Unmanaged<AnyObject>?,
                                                                      _ flags: os_activity_flag_t) -> AnyObject!

class IOSActivityContextManager: ContextManager {
    private let logger = OSLog(subsystem: "co.elastic.iOSActivityContextManager", category: "TracingContext")
    
    static let instance = IOSActivityContextManager()

    let rlock = NSRecursiveLock()

    // map activity id to stack of spans
    var contextMap = [os_activity_id_t: [String: ActivityStack]]()
    
    class Activity {
        init(id: os_activity_id_t) {
            self.id = id
        }

        var id: os_activity_id_t
    }
    
    // map root span to corresponding activity id
    var rootToActivityMap = NSMapTable<AnyObject, Activity>(keyOptions: .weakMemory, valueOptions: .strongMemory)
    
    // retrieve current value based on the current activity
    func getCurrentContextValue(forKey key: OpenTelemetryContextKeys) -> AnyObject? {
        var parentIdent: os_activity_id_t = 0
        let activityIdent = os_activity_get_identifier(OS_ACTIVITY_CURRENT, &parentIdent)
        var contextValue: AnyObject?
        rlock.lock()
        guard let context = contextMap[activityIdent] ?? contextMap[parentIdent] else {
            rlock.unlock()
            return nil
        }
        contextValue = context[key.rawValue]?.peek()
        rlock.unlock()
        return contextValue
    }

    func setCurrentContextValue(forKey key: OpenTelemetryContextKeys, value: AnyObject) {
        var parentIdent: os_activity_id_t = 0
        var activityIdent = os_activity_get_identifier(OS_ACTIVITY_CURRENT, &parentIdent)
        rlock.lock()
        
        if contextMap[activityIdent] == nil || contextMap[activityIdent]?[key.rawValue] == nil {
            var scope: os_activity_scope_state_s
            // create new activity only in case of a root span
            // or when key is not a span type and no current activity exists
            var shouldCreateActivity : Bool = false
            
            if let span = value as? RecordEventsReadableSpan {
                shouldCreateActivity = span.parentContext == nil
            } else {
                shouldCreateActivity = activityIdent == 0
            }
            
            // create empty span stack for the created activity
            if (shouldCreateActivity) {
                (activityIdent, scope) = createActivityContext()
                rootToActivityMap.setObject(Activity(id: activityIdent), forKey: value)
                contextMap[activityIdent] = [String: ActivityStack]()
                contextMap[activityIdent]?[key.rawValue] = ActivityStack(scopeState: scope)
            }
        }
        // put span on top of the stack
        contextMap[activityIdent]?[key.rawValue]?.push(value)
        rlock.unlock()
    }

    func createActivityContext() -> (os_activity_id_t, os_activity_scope_state_s) {
        let dso = UnsafeMutableRawPointer(mutating: #dsohandle)
        let activity = _os_activity_create(dso, "ActivityContext", OS_ACTIVITY_CURRENT, OS_ACTIVITY_FLAG_DEFAULT)
        let currentActivityId = os_activity_get_identifier(activity, nil)
        var activityState = os_activity_scope_state_s()
        os_activity_scope_enter(activity, &activityState)
        return (currentActivityId, activityState)
    }

    func removeContextValue(forKey key: OpenTelemetryContextKeys, value: AnyObject) {
        rlock.lock()
        if let activityIdent = rootToActivityMap.object(forKey: value)?.id {
            // Root span has ended, so need to clean up context.
            // Waiting half a second for any requests related to the root span (that start late)
            // to start before removing the context for the root span.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.rlock.lock()
                if let stack = self.contextMap[activityIdent]?[key.rawValue] {
                    var scopeState = stack.scopeState
                    // leave activity scope
                    os_activity_scope_leave(&scopeState)
                }
                
                self.contextMap[activityIdent]?.removeValue(forKey: key.rawValue)
                if (self.contextMap[activityIdent] != nil && self.contextMap[activityIdent]!.isEmpty) {
                    self.contextMap.removeValue(forKey: activityIdent)
                }
                self.rootToActivityMap.removeObject(forKey: value)
                self.rlock.unlock()
            }
            
        } else {
            // span ended that is not root, just removing it from the stack of the current activity
            let activityIdent = os_activity_get_identifier(OS_ACTIVITY_CURRENT, nil)
            if var stack = contextMap[activityIdent]?[key.rawValue] {
                stack.remove(value)
            }
        }
        rlock.unlock()
    }
}
