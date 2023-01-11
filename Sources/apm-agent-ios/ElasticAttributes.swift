// Copyright © 2022 Elasticsearch BV
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

public enum ElasticAgent: String {
    case name = "apm-agent-ios"
}

public enum ElasticAttributes: String {
    /**
    Timestamp applied to all spans at time of export. To help with clock drift.
     */
    case exportTimestamp = "telemetry.sdk.elastic_export_timestamp"
    
    /**
    The id of the device
     */
    case deviceIdentifier = "device.id"
    
    /**
        histogram metric describing application launch time
     */
    
}

public enum ElasticMetrics : String {
    case appLaunchTime = "application.launch.time"
    case appHangtime = "application.responsiveness.hangtime"
    case appExits = "application.exits"
}
