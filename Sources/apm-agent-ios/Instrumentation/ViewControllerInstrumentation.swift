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
import UIKit
import OpenTelemetryApi
import OpenTelemetrySdk

internal class ViewControllerInstrumentation {
    
    let viewDidLoad : ViewDidLoad
    let viewDidAppear : ViewDidAppear
    let viewDidDisappear : ViewDidDisappear
    let viewWillDisappear : ViewWillDisappear
    init() throws {
        viewDidLoad = try ViewDidLoad.build()
        viewDidAppear = try ViewDidAppear.build()
        viewDidDisappear = try ViewDidDisappear.build()
        viewWillDisappear = try ViewWillDisappear.build()

    }
    
    func swizzle() {
        viewDidLoad.swizzle()
        viewDidAppear.swizzle()
        viewDidDisappear.swizzle()
        viewWillDisappear.swizzle()
    }
    
    
    static func getTracer() -> TracerSdk {
        OpenTelemetrySDK.instance.tracerProvider.get(instrumentationName: "UIViewController", instrumentationVersion: "0.0.1") as! TracerSdk
    }
    
    class ViewDidLoad : MethodSwizzler<
        @convention(c) (UIViewController, Selector) -> Void, //IMPSignature
        @convention(block) (UIViewController) -> Void //BlockSignature
    > {
        static func build() throws -> ViewDidLoad {
            try ViewDidLoad(selector: #selector(UIViewController.viewDidLoad), klass: UIViewController.self)
        }
        func swizzle() {
            swap { previousImplementation -> BlockSignature in
                { viewController -> Void in
                
                        TraceLogger.startTrace(tracer: ViewControllerInstrumentation.getTracer(),
                                           associatedObject: viewController,
                                           name: "\(type(of: viewController))#viewDidLoad")
                    previousImplementation(viewController, self.selector)
                    TraceLogger.stopTrace(associatedObject: viewController)

                }
            }
        }
    }

    class ViewDidAppear: MethodSwizzler<
        @convention(c) (UIViewController, Selector, Bool) -> Void, //IMPSignature
        @convention(block) (UIViewController, Bool) -> Void //BlockSignature
    > {
        static func build() throws -> ViewDidAppear {
            try ViewDidAppear(selector: #selector(UIViewController.viewDidAppear), klass: UIViewController.self)
        }
        func swizzle() {
            swap { previousImplementation -> BlockSignature in
                { viewController, animated -> Void in
                    // it not already started
                    // start a trace
                    TraceLogger.startTrace(tracer: ViewControllerInstrumentation.getTracer(),
                                       associatedObject: viewController,
                                       name: "\(type(of:viewController))#viewDidAppear")
                  previousImplementation(viewController,self.selector , animated)
                    TraceLogger.stopTrace(associatedObject: viewController)
                }
            }
        }
    }

    class ViewDidDisappear: MethodSwizzler<
            @convention(c) (UIViewController, Selector, Bool) -> Void, //IMPSignature
            @convention(block) (UIViewController, Bool) -> Void //BlockSignature
    > {
        static func build() throws -> ViewDidDisappear {
            try ViewDidDisappear(selector: #selector(UIViewController.viewDidDisappear),klass: UIViewController.self)
        }
        func swizzle() {
            swap { previousImplementation -> BlockSignature in
                { viewController, animated -> Void in
                    TraceLogger.startTrace(tracer: ViewControllerInstrumentation.getTracer(),
                                       associatedObject: viewController,
                                       name: "\(type(of:viewController))#viewDidDisappear")
                    previousImplementation(viewController, self.selector, animated)
                    // complete trace
                    TraceLogger.stopTrace(associatedObject: viewController)
                }
            }
        }
    }
    
    class ViewWillDisappear: MethodSwizzler<
            @convention(c) (UIViewController, Selector, Bool) -> Void, //IMPSignature
            @convention(block) (UIViewController, Bool) -> Void //BlockSignature
    > {
        static func build() throws -> ViewWillDisappear {
            try ViewWillDisappear(selector: #selector(UIViewController.viewWillDisappear),klass: UIViewController.self)
        }
        func swizzle() {
            swap { previousImplementation -> BlockSignature in
                { viewController, animated -> Void in
                    TraceLogger.startTrace(tracer: ViewControllerInstrumentation.getTracer(),
                                       associatedObject: viewController,
                                       name: "\(type(of:viewController))#viewWillDisappear")
                    previousImplementation(viewController, self.selector, animated)
                    // complete trace
                    TraceLogger.stopTrace(associatedObject: viewController)
                }
            }
        }
    }
}

#endif // #if os(iOS)
