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
@_implementationOnly import NIOConcurrencyHelpers
import OpenTelemetryApi
@_implementationOnly import OpenTelemetrySdk
import SwiftUI
import UIKit
import os

@available(iOS 13.0, *)
public extension View {
  func reportName(_ name: String) -> Self {
    VCNameOverrideStore.shared().name = name
    return self
  }
}

internal class VCNameOverrideStore {
  let nameLock = NIOLock()
  private var _name = ""
  public var name: String {
    get {
      var newValue = ""
      nameLock.withLockVoid {
        newValue = self._name
      }
      return newValue
    }
    set {
      nameLock.withLockVoid {
        self._name = newValue
      }
    }
  }
  static var instance = VCNameOverrideStore()
  private init() {
  }

  static func shared() -> VCNameOverrideStore {
    return instance
  }
}

internal class ViewControllerInstrumentation {
  static let logger = OSLog(subsystem: "co.elastic.viewControllerInstrumentation", category: "Instrumentation")
  var activeSpan: Span?
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
    //            viewDidLoad.swizzle()
    viewWillAppear.swizzle()
    viewDidAppear.swizzle()
  }

  static func getTracer() -> Tracer {
    OpenTelemetry.instance.tracerProvider.get(instrumentationName: "UIViewController",
                                              instrumentationVersion: "0.0.3")
  }

  static func getViewControllerName(_ viewController: UIViewController) -> String? {
    var title = viewController.navigationItem.title

    if let accessibiltyLabel = viewController.accessibilityLabel, !accessibiltyLabel.isEmpty {
      title = "\(accessibiltyLabel) - view appearing"
    } else if let navTitle = title {
      title = "\(navTitle) - view appearing"
    }
    return title
  }

  class ViewDidLoad: MethodSwizzler<
  @convention(c) (UIViewController, Selector) -> Void, // IMPSignature
  @convention(block) (UIViewController) -> Void // BlockSignature
  > {
    static func build() throws -> ViewDidLoad {
      try ViewDidLoad(selector: #selector(UIViewController.viewDidLoad), klass: UIViewController.self)
    }

    func swizzle() {
      swap { previousImplementation -> BlockSignature in { viewController in

        let name = "\(type(of: viewController)) - view loading"
        _ = ViewControllerInstrumentation
          .traceLogger
          .startTrace(tracer: ViewControllerInstrumentation.getTracer(),
                      associatedObject: viewController,
                      name: name,
                      preferredName: ViewControllerInstrumentation.getViewControllerName(viewController))

        previousImplementation(viewController, self.selector)
        ViewControllerInstrumentation
          .traceLogger
          .stopTrace(associatedObject: viewController,
                     preferredName: name)
      }}
    }
  }

  class ViewWillAppear: MethodSwizzler<
  @convention(c) (UIViewController, Selector, Bool) -> Void,
  @convention(block) (UIViewController, Bool) -> Void
  > {
    static func build() throws -> ViewWillAppear {
      try ViewWillAppear(selector: #selector(UIViewController.viewWillAppear), klass: UIViewController.self)
    }

    func swizzle() {
      swap { previousImplementation -> BlockSignature in { viewController, animated in

        let name = "\(type(of: viewController)) - view appearing"

        _ = ViewControllerInstrumentation
          .traceLogger
          .startTrace(tracer: ViewControllerInstrumentation.getTracer(),
                      associatedObject: viewController,
                      name: name,
                      preferredName: ViewControllerInstrumentation.getViewControllerName(viewController))
        previousImplementation(viewController, self.selector, animated)

      }}
    }
  }

  class ViewDidAppear: MethodSwizzler<
  @convention(c) (UIViewController, Selector, Bool) -> Void, // IMPSignature
  @convention(block) (UIViewController, Bool) -> Void // BlockSignature
  > {
    static func build() throws -> ViewDidAppear {
      try ViewDidAppear(selector: #selector(UIViewController.viewDidAppear), klass: UIViewController.self)
    }
    func swizzle() {
      swap { previousImplementation -> BlockSignature in { viewController, animated in
        previousImplementation(viewController, self.selector, animated)
        ViewControllerInstrumentation
          .traceLogger
          .stopTrace(associatedObject: viewController,
                     preferredName: getViewControllerName(viewController))
      }}
    }
  }
}

#endif // #if os(iOS)
