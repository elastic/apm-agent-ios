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

import Foundation
import UIKit
import OpenTelemetryApi
public class ApplicationLifecycleInstrumentation: NSObject {
    private static let eventName: String = "lifecycle"
    private enum state: String {
        case active
        case inactive
        case background
        case foreground
        case terminate
}
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    static func getLogger() -> Logger {
        OpenTelemetry.instance.loggerProvider.loggerBuilder(instrumentationScopeName: "ApplicationLifecycle").setEventDomain("device")
            .build()
    }

    public override init() {
        super.init()

        NotificationCenter.default.addObserver(self, selector: #selector(active(_:)), name: UIApplication.didBecomeActiveNotification, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(inactive(_:)), name: UIApplication.willResignActiveNotification, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(background(_:)), name: UIApplication.didEnterBackgroundNotification, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(foreground(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(terminate(_:)), name: UIApplication.willTerminateNotification, object: nil)
    }

    @objc func active(_ notification: Notification) {
        Self.getLogger().eventBuilder(name: Self.eventName)
            .setAttributes(["lifecycle.state": AttributeValue.string(state.active.rawValue)])
            .emit()
    }

    @objc func inactive(_ notification: Notification) {
        Self.getLogger().eventBuilder(name: Self.eventName)
            .setAttributes(["lifecycle.state": AttributeValue.string(state.inactive.rawValue)])
            .emit()
    }

    @objc func background(_ notification: Notification) {
        Self.getLogger().eventBuilder(name: Self.eventName)
            .setAttributes(["lifecycle.state": AttributeValue.string(state.background.rawValue)])
            .emit()
    }

    @objc func foreground(_ notification: Notification) {
        Self.getLogger().eventBuilder(name: Self.eventName)
            .setAttributes(["lifecycle.state": AttributeValue.string(state.foreground.rawValue)])
            .emit()
    }

    @objc func terminate(_ notification: Notification) {
        Self.getLogger().eventBuilder(name: Self.eventName)
            .setAttributes(["lifecycle.state": AttributeValue.string(state.terminate.rawValue)])
            .emit()}
}
