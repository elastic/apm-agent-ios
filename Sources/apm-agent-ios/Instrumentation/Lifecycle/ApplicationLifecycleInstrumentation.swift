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
public class ApplicationLifecycleInstrumentation : NSObject  {
    let logger : Logger
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    public override init() {
        logger = OpenTelemetry.instance.loggerProvider.loggerBuilder(instrumentationScopeName: "Application.Lifecycle").setEventDomain("device")
            .build()
        
        super.init()
        
        NotificationCenter.default.addObserver(self, selector: #selector(active(_:)), name: UIApplication.didBecomeActiveNotification , object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(inactive(_:)), name: UIApplication.willResignActiveNotification , object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(background(_:)), name: UIApplication.didEnterBackgroundNotification , object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(foreground(_:)), name: UIApplication.willEnterForegroundNotification , object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(terminate(_:)), name: UIApplication.willTerminateNotification , object: nil)
    }
    
    @objc func active(_ notification: Notification) {
        logger.eventBuilder(name: "lifecycle")
            .setAttributes(["lifecycle.state": AttributeValue.string("active")])
            .emit()

    }
    @objc func inactive(_ notification: Notification){
        logger.eventBuilder(name: "inactive")
            .setAttributes(["lifecycle.state": AttributeValue.string("active")])
            .emit()
    }
    @objc func background(_ notification: Notification) {
        logger.eventBuilder(name: "background")
            .setAttributes(["lifecycle.state": AttributeValue.string("active")])
            .emit()
    }
    @objc func foreground(_ notification: Notification) {
        logger.eventBuilder(name: "lifecycle")
            .setAttributes(["lifecycle.state": AttributeValue.string("foreground")])
            .emit()
    }
    @objc func terminate(_ notification: Notification) {
        logger.eventBuilder(name: "lifecycle")
            .setAttributes(["lifecycle.state": AttributeValue.string("terminate")])
            .emit()}
}
