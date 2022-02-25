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

    internal class ViewControllerInstrumentation {
        var activeSpan : Span? = nil
        static let traceLogger = TraceLogger()
        let viewDidLoad: ViewDidLoad
        let viewWillAppear: ViewWillAppear
        let viewDidAppear: ViewDidAppear

        init() throws {
            viewDidLoad = try ViewDidLoad.build()
            viewWillAppear = try ViewWillAppear.build()
            viewDidAppear = try ViewDidAppear.build()
        }

        deinit {
            NotificationCenter.default.removeObserver(TraceLogger.self)
        }

        func swizzle() {
            viewDidLoad.swizzle()
            viewWillAppear.swizzle()
            viewDidAppear.swizzle()
        }

        static func getTracer() -> TracerSdk {
            OpenTelemetrySDK.instance.tracerProvider.get(instrumentationName: "UIViewController", instrumentationVersion: "0.0.2") as! TracerSdk
        }

        
        class ViewDidLoad: MethodSwizzler<
        @convention(c) (UIViewController, Selector) -> Void, // IMPSignature
            @convention(block) (UIViewController) -> Void // BlockSignature
            >
            {
                static func build() throws -> ViewDidLoad {
                    try ViewDidLoad(selector: #selector(UIViewController.viewDidLoad), klass: UIViewController.self)
                }

                    func swizzle() {
                        swap { previousImplementation -> BlockSignature in
                            { viewController -> Void in
                                
                            var title = viewController.navigationItem.title
                                
                            if let navTitle = title {
                                title = "\(navTitle) - view appearing"
                            }
                                
                            let name = "\(type(of: viewController)) - view appearing"
                            
                            _ = ViewControllerInstrumentation.traceLogger.startTrace(tracer: ViewControllerInstrumentation.getTracer(), associatedObject: viewController, name: name, preferredName: title)
                            previousImplementation(viewController, self.selector)
                        }
                    }
                }
            }

        class ViewWillAppear: MethodSwizzler<
        @convention(c) (UIViewController, Selector, Bool) -> Void,
            @convention(block) (UIViewController, Bool) -> Void
            >
            {
                static func build() throws -> ViewWillAppear {
                    try ViewWillAppear(selector: #selector(UIViewController.viewWillAppear), klass: UIViewController.self)
                }

                func swizzle() {
                    swap { previousImplementation -> BlockSignature in
                        { viewController, animated -> Void in
                            var title = viewController.navigationItem.title
                            
                            if let navTitle = title {
                                title = "\(navTitle) - view appearing"
                            }
                                                    
                            let name = "\(type(of: viewController)) - view appearing"

                            _ = ViewControllerInstrumentation.traceLogger.startTrace(tracer: ViewControllerInstrumentation.getTracer(), associatedObject: viewController, name: name, preferredName: title)

                            previousImplementation(viewController, self.selector, animated)
                        }
                    }
                }
            }

        class ViewDidAppear: MethodSwizzler<
        @convention(c) (UIViewController, Selector, Bool) -> Void, // IMPSignature
            @convention(block) (UIViewController, Bool) -> Void // BlockSignature
            >
            {
                static func build() throws -> ViewDidAppear {
                    try ViewDidAppear(selector: #selector(UIViewController.viewDidAppear), klass: UIViewController.self)
                }
                func swizzle() {
                    swap { previousImplementation -> BlockSignature in
                        { viewController, animated -> Void in
                            previousImplementation(viewController, self.selector, animated)
                            ViewControllerInstrumentation.traceLogger.stopTrace(associatedObject: viewController)
                        }
                    }
                }
            }
    }

#endif // #if os(iOS)
