// Copyright © 2023 Elasticsearch BV
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

#if canImport(UIKit) && !os(watchOS)
import Foundation
import UIKit
import OpenTelemetryApi
public class ApplicationLifecycleInstrumentation: NSObject {
    // https://opentelemetry.io/docs/specs/semconv/mobile/mobile-events/
    private static let eventName = "device.app.lifecycle"
    private let useLegacyAttributeNames: Bool

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    static func getLogger() -> Logger {
        OpenTelemetry
            .instance
            .loggerProvider
            .loggerBuilder(instrumentationScopeName: "ApplicationLifecycle")
            .build()
    }

    public override init() {
        useLegacyAttributeNames = false
        super.init()
        registerObservers()
    }

    init(useLegacyAttributeNames: Bool) {
        self.useLegacyAttributeNames = useLegacyAttributeNames
        super.init()
        registerObservers()
    }

    private func registerObservers() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(active(_:)),
                                               name: UIApplication.didBecomeActiveNotification,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(inactive(_:)),
                                               name: UIApplication.willResignActiveNotification,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(background(_:)),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(foreground(_:)),
                                               name: UIApplication.willEnterForegroundNotification,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(terminate(_:)),
                                               name: UIApplication.willTerminateNotification,
                                               object: nil)
    }

    @objc func active(_ notification: Notification) {
        emit(state: .active)
    }

    @objc func inactive(_ notification: Notification) {
        emit(state: .inactive)
    }

    @objc func background(_ notification: Notification) {
        emit(state: .background)
    }

    @objc func foreground(_ notification: Notification) {
        emit(state: .foreground)
    }

    @objc func terminate(_ notification: Notification) {
        emit(state: .terminate)
    }

    private func emit(state: SemanticConventions.Ios.AppStateValues) {
        let eventName = useLegacyAttributeNames
            ? LegacyAttributeNames.lifecycleEvent
            : Self.eventName
        let stateAttribute = useLegacyAttributeNames
            ? LegacyAttributeNames.lifecycleState
            : SemanticConventions.Ios.appState.rawValue

        Self.getLogger().logRecordBuilder()
            .setEventName(eventName)
            .setAttributes([stateAttribute: AttributeValue.string(state.description)])
            .emit()
    }
}

#endif
