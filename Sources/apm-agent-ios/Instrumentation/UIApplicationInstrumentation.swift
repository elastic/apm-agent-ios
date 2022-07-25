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

#if os(iOS)
    import Foundation
    import OpenTelemetryApi
    import OpenTelemetrySdk
    import SwiftUI
    import UIKit

    internal class UIApplicationInstrumentation {
        let configuration: UIApplicationInstrumentationConfiguration
        let sendEvent: SendEvent

        static func tracer() -> TracerSdk {
            OpenTelemetrySDK.instance.tracerProvider.get(instrumentationName: "UIApplication", instrumentationVersion: "0.0.1") as! TracerSdk
        }

        init(configuration: UIApplicationInstrumentationConfiguration = UIApplicationInstrumentationConfiguration.defaultConfiguration) throws {
            self.configuration = configuration
            sendEvent = try SendEvent.build(config: self.configuration)
        }

        func swizzle() {
            //sendEvent.swizzle()
        }

        class SendEvent: MethodSwizzler<
        @convention(c) (UIApplication, Selector, UIEvent) -> Void,
            @convention(block) (UIApplication, UIEvent) -> Void
            >
            {
                public var config: UIApplicationInstrumentationConfiguration

                init(config: UIApplicationInstrumentationConfiguration) throws {
                    self.config = config
                    try super.init(selector: #selector(UIApplication.sendEvent), klass: UIApplication.self)
                }

                internal required init(selector _: Selector, klass _: AnyClass) throws {
                    config = UIApplicationInstrumentationConfiguration.defaultConfiguration
                    try super.init(selector: #selector(UIApplication.sendEvent), klass: UIApplication.self)
                }

                static func build(config: UIApplicationInstrumentationConfiguration) throws -> SendEvent {
                    try SendEvent(config: config)
                }

                func swizzle() {
                    swap { previousImplementation -> BlockSignature in
                        { application, event -> Void in
                            var span: Span?
                            if self.config.shouldInstrumentEvent(type: event.type) {
                                span = TouchLogger.startTrace(tracer: UIApplicationInstrumentation.tracer(),
                                                              event: event,
                                                              config: self.config)
                            }

                            previousImplementation(application, self.selector, event)

                            span?.status = .ok
                            span?.end()
                        }
                    }
                }
            }
    }

#endif
