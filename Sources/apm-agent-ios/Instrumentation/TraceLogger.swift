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
import OpenTelemetryApi
import OpenTelemetrySdk
    
class TraceLogger {
    private static var associatedObjectKey : UInt8 = 0
    
    static func startTrace(tracer: TracerSdk, associatedObject: AnyObject, name: String) {
        guard let _ = objc_getAssociatedObject(associatedObject, &Self.associatedObjectKey) as? OpenTelemetryApi.Span else {
           let builder = tracer.spanBuilder(spanName: "\(name)")
            .setSpanKind(spanKind: .server)
    
            
            
            let span = builder.startSpan()
            
            
            print("Started Span \"\(name)\" (\(span.context.traceId.hexString)-\(span.context.spanId.hexString))")
            objc_setAssociatedObject(associatedObject, &Self.associatedObjectKey, span, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN)
            return
        }
    }
    
    static func stopTrace(associatedObject: AnyObject) {
        if let span = objc_getAssociatedObject(associatedObject, &Self.associatedObjectKey) as? Span {
            span.status = .ok;
            span.end()
            print("ended span \"\(span.name)\" (\(span.context.traceId.hexString)-\(span.context.spanId.hexString))")
            objc_setAssociatedObject(associatedObject, &Self.associatedObjectKey, nil, objc_AssociationPolicy.OBJC_ASSOCIATION_ASSIGN)
        }
    }
}
