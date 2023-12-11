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
  private var activeSpan: Span?
  private var loadCount: Int = 0
  private let spanLock = NSRecursiveLock()
  private let logger = OSLog(subsystem: "co.elastic.viewControllerInstrumentation", category: "Instrumentation")

  func startTrace(tracer: Tracer, associatedObject: AnyObject, name: String, preferredName: String?) -> Span? {
    spanLock.lock()
    defer {
      spanLock.unlock()
    }
    loadCount+=1
    var activeSpan = getActiveSpan()

    if activeSpan == nil {
      let builder = tracer.spanBuilder(spanName: "\(name)")
        .setActive(true)
        .setNoParent()
        .setSpanKind(spanKind: .client)

      let span = builder.startSpan()
      os_log("Started trace: %@ - %@ - %@",
             log: logger,
             type: .debug,
             name,
             span.context.traceId.description,
             span.context.spanId.description)

      setActiveSpan(span)
      activeSpan = span
    }

    if let span = activeSpan {
      OpenTelemetry.instance.contextProvider.setActiveSpan(span)

    }

    if let preferredName = preferredName, activeSpan?.name != preferredName {
      activeSpan?.name = preferredName

    }
    return activeSpan
  }

  func stopTrace(associatedObject: AnyObject, preferredName: String?) {
    spanLock.lock()
    defer {
      spanLock.unlock()
    }

    if let activeSpan = getActiveSpan() {
      if let preferredName = preferredName, activeSpan.name != preferredName {
        activeSpan.name = preferredName
      }
      if !VCNameOverrideStore.shared().name.isEmpty {
        activeSpan.name = VCNameOverrideStore.shared().name
        VCNameOverrideStore.shared().name = ""
      }
      OpenTelemetry.instance.contextProvider.removeContextForSpan(activeSpan)
    }

    loadCount -= 1

    if  let associatedSpan = getActiveSpan(), loadCount == 0 {
      os_log("Stopping trace: %@ - %@ - %@",
             log: logger,
             type: .debug,
             associatedSpan.name,
             associatedSpan.context.traceId.description,
             associatedSpan.context.spanId.description)

      associatedSpan.status = .ok
      associatedSpan.end()
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
  }

}
#endif // #if os(iOS)
