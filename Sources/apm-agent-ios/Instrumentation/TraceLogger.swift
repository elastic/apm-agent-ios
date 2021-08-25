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
    private static var objectKey: UInt8 = 0

    @objc static func didEnterBackground() {
        OpenTelemetrySDK.instance.contextProvider.activeSpan?.addEvent(name: "application entered background")
    }

    static func startTrace(tracer: TracerSdk, associatedObject: AnyObject, name: String) {
        guard let _ = objc_getAssociatedObject(associatedObject, UnsafeRawPointer(&Self.objectKey)) as? OpenTelemetryApi.Span else {
            let builder = tracer.spanBuilder(spanName: "\(name)")
                .setSpanKind(spanKind: .client)

            let span = builder.startSpan()
            OpenTelemetrySDK.instance.contextProvider.setActiveSpan(span)

            objc_setAssociatedObject(associatedObject, UnsafeRawPointer(&Self.objectKey), span, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN)
            return
        }
    }

    static func stopTrace(associatedObject: AnyObject) {
        if let span = objc_getAssociatedObject(associatedObject, UnsafeRawPointer(&Self.objectKey)) as? Span {
            span.status = .ok
            span.end()
            objc_setAssociatedObject(associatedObject, UnsafeRawPointer(&Self.objectKey), nil, objc_AssociationPolicy.OBJC_ASSOCIATION_ASSIGN)
        }
    }
}
