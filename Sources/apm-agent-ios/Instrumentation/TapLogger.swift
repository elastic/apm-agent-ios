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
import UIKit
import OpenTelemetryApi
import OpenTelemetrySdk
import os

class TouchLogger {
    private static var objectKey : UInt8 = 0
    static func startTrace(tracer: TracerSdk, touch : UITouch) {
        if let parentVc = TouchLogger.findViewController(ofView: touch.view), let view = touch.view {
            if view is UITableView { //todo: make configurable
                return
            }
            let spanName = "tapped \(type(of:view)) in \(type(of:parentVc))"
           
            os_log("%@",spanName)
            
            // todo: shouldTrace?
            let span = tracer.spanBuilder(spanName: spanName).setSpanKind(spanKind: .client).startSpan()
            OpenTelemetrySDK.instance.contextProvider.setActiveSpan(span)
            objc_setAssociatedObject(touch, UnsafeRawPointer(&Self.objectKey), span, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    static func stopTrace(tracer: TracerSdk, touch: UITouch) {
        if let span = objc_getAssociatedObject(touch,  UnsafeRawPointer(&Self.objectKey)) as? Span {
            span.status = .ok;
            span.end()
            objc_setAssociatedObject(touch,  UnsafeRawPointer(&Self.objectKey), nil, objc_AssociationPolicy.OBJC_ASSOCIATION_ASSIGN)
        }
    }
    
    static func findViewController(ofView: UIView?) -> UIViewController? {
        guard let view = ofView else {
            return nil
        }
        if let nextResponder = view.next as? UIViewController {
            return nextResponder
        } else if let nextResponder = view.next as? UIView {
            return TouchLogger.findViewController(ofView: nextResponder)
        } else {
            return nil
        }
    }
}
