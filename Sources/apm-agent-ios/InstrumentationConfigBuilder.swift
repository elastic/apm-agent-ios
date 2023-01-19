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


public class InstrumentationConfigBuilder {
    var enableCrashReporting : Bool?
    var enableAgent : Bool?
    
    public init() {}
    
    public func withCrashReporting(_ enable: Bool) -> Self {
        self.enableCrashReporting = enable
        return self
    }
    
    public func disableAgent() -> Self {
        enableAgent = false
        return self
    }
    
    public func build() -> InstrumentationConfiguration {
        var config = InstrumentationConfiguration()
        if let enableAgent = self.enableAgent {
            config.enableAgent = enableAgent
        }
        
        if let enableCrashReporting = self.enableCrashReporting  {
            config.enableCrashReporting = enableCrashReporting
        }
        return config
    }
}
