//
// Created by Bryce Buchanan on 8/23/21.
//

#if os(iOS)

    import Foundation
    import UIKit
    class UIApplicationInstrumentationConfiguration {
        public let filter: Set<String>
        public let useAccessibility: Bool
        public let events: Set<UIEvent.EventType>
        public let shouldInstrumentEvent: ((UIEvent) -> Bool?)?
        public let customName: ((UITouch, String) -> String?)?

        private init(filter: Set<String>, events: Set<UIEvent.EventType>, useAccessibility: Bool, shouldInstrumentEvent: ((UIEvent) -> Bool?)?, customName: ((UITouch, String) -> String?)?) {
            self.filter = filter
            self.events = events
            self.shouldInstrumentEvent = shouldInstrumentEvent
            self.customName = customName
            self.useAccessibility = useAccessibility
        }

        public static var defaultConfiguration: UIApplicationInstrumentationConfiguration {
            UIApplicationInstrumentationConfiguration(filter: Set<String>(), events: defaultEvents, useAccessibility: true, shouldInstrumentEvent: nil, customName: nil)
        }

        public static var defaultEvents: Set<UIEvent.EventType> {
            Set<UIEvent.EventType>([.touches])
        }

        func shouldFilter(cls: AnyClass) -> Bool {
            filter.contains(String(describing: cls))
        }

        func shouldInstrumentEvent(type: UIEvent.EventType) -> Bool {
            events.contains(type)
        }

        class Builder {
            private var useAccessibility: Bool = true
            private var classFilter = Set<String>()
            private var events = Set<UIEvent.EventType>()
            public let shouldInstrumentEvent: ((UIEvent) -> Bool?)? = nil
            public let customName: ((UITouch, String) -> String?)? = nil
            public func defaultEvents() -> Self {
                self
            }

            public func useAccessibility(_ use: Bool) -> Self {
                useAccessibility = use
                return self
            }

            public func addEventType(type: UIEvent.EventType) -> Self {
                events.insert(type)
                return self
            }

            public func addTargetFilter(for cls: AnyClass) -> Self {
                classFilter.insert(String(describing: type(of: cls)))
                return self
            }

            func addTargetFilter(for cls: String) -> Self {
                classFilter.insert(cls)
                return self
            }

            public func addTargetFilters(for classes: [AnyClass]) -> Self {
                for element in classes {
                    _ = addTargetFilter(for: element)
                }

                return self
            }

            public func addTargetFilters(for classes: [String]) -> Self {
                for element in classes {
                    _ = addTargetFilter(for: element)
                }
                return self
            }

            public func build() -> UIApplicationInstrumentationConfiguration {
                UIApplicationInstrumentationConfiguration(filter: classFilter, events: events,
                                                          useAccessibility: useAccessibility,
                                                          shouldInstrumentEvent: shouldInstrumentEvent,
                                                          customName: customName)
            }
        }
    }
#endif // os(iOS)
