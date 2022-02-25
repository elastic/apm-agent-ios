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
#if os(iOS)
import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import SwiftUI
import UIKit
import os


class TraceLogger {
    private static var objectKey: UInt8 = 0
    private static var timerKey: UInt8 = 0
    private var activeSpan : Span? = nil
    private let spanLock = NSRecursiveLock()
    private let logger = OSLog(subsystem: "co.elastic.viewControllerInstrumentation", category: "Instrumentation")
    
    func startTrace(tracer: TracerSdk, associatedObject: AnyObject, name: String, preferredName: String?) -> Span? {
        spanLock.lock()
        defer {
            spanLock.unlock()
        }
        guard let activeSpan = getActiveSpan() else {
            let builder = tracer.spanBuilder(spanName: "\(name)")
                .setActive(true)
                .setSpanKind(spanKind: .client)
            
            let span = builder.startSpan()
            span.setAttribute(key: "type", value: AttributeValue.string("mobile"))
            
            os_log("Starting trace: %@ - %@ - %@",log:logger,type:.debug,name, span.context.traceId.description, span.context.spanId.description)
            span.setAttribute(key: "session.id", value: SessionManager.instance.session())
            setActiveSpan(span)
            setAssociatedSpan(associatedObject,span)
            return span
        }
        if let preferredName = preferredName, activeSpan.name != preferredName {
            os_log("renaming trace: %@ -> %@ - %@ - %@", log:logger, type:.debug, activeSpan.name, preferredName, activeSpan.context.traceId.description, activeSpan.context.spanId.description)
                activeSpan.name = preferredName
    
        }
        return activeSpan
    }
    
    func stopTrace(associatedObject: AnyObject) {
        spanLock.lock()
        defer {
            spanLock.unlock()
        }
        if let associatedSpan = getAssociatedSpan(associatedObject), associatedSpan === getActiveSpan() {
            os_log("Stopping trace: %@ - %@ - %@", log:logger, type:.debug,associatedSpan.name,associatedSpan.context.traceId.description, associatedSpan.context.spanId.description)
            associatedSpan.status = .ok
            associatedSpan.end()
            clearAssociatedSpan(associatedObject)
            setActiveSpan(nil)
        }
    }

    func setActiveSpan(_ span: Span?) {
        spanLock.lock()
        defer {
            spanLock.unlock()
        }
        activeSpan = span
    }
    func getActiveSpan() -> Span? {
        spanLock.lock()
        defer {
            spanLock.unlock()
        }
        return activeSpan
        /* contextProvider isn't dependible at this time */
        // return OpenTelemetry.instance.contextProvider.activeSpan
    }

    func setAssociatedSpan(_ vc: AnyObject, _ span: Span) {
        objc_setAssociatedObject(vc, UnsafeRawPointer(&Self.objectKey), span, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN)
    }
    func getAssociatedSpan(_ vc: AnyObject) -> Span? {
        return objc_getAssociatedObject(vc, UnsafeRawPointer(&Self.objectKey)) as? OpenTelemetryApi.Span
    }
    func clearAssociatedSpan(_ vc: AnyObject) {
        objc_setAssociatedObject(vc, UnsafeRawPointer(&Self.objectKey), nil, objc_AssociationPolicy.OBJC_ASSOCIATION_ASSIGN)

    }
        
}
#endif // #if os(iOS)
