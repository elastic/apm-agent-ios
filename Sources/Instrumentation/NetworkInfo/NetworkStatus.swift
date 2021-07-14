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
import CoreTelephony
import Network
import Reachability

public class NetworkStatus {
    public private(set) var networkInfo : CTTelephonyNetworkInfo
    public private(set) var networkMonitor : INetworkMonitor
    public convenience init() throws {
        self.init(with:try NetworkMonitor())
    }
    
    public init(with monitor: INetworkMonitor, info: CTTelephonyNetworkInfo = CTTelephonyNetworkInfo()) {
        self.networkMonitor = monitor
        networkInfo = info
    
    }

    public func status() -> (String, String? ,CTCarrier?) {
        switch networkMonitor.getConnection() {
        case .wifi:
            return ("wifi",nil,nil)
        case .cellular:
            if #available(iOS 13.0, *) {
                if let serviceId = networkInfo.dataServiceIdentifier, let value = networkInfo.serviceCurrentRadioAccessTechnology?[serviceId] {
                    return ("cell", simpleConnectionName(connectionType: value), networkInfo.serviceSubscriberCellularProviders?[networkInfo.dataServiceIdentifier!])
                }
            } else {
                if let radioType = networkInfo.currentRadioAccessTechnology {
                return ("cell", simpleConnectionName(connectionType: radioType), networkInfo.subscriberCellularProvider)
                }
            }
            return ("cell","unknown", nil)
        case .unavailable:
            return ("unavailable",nil , nil)
        }
    }
    
    func simpleConnectionName(connectionType: String) -> String {
        switch connectionType {
        case "CTRadioAccessTechnologyEdge":
            return "GPRS"
        case "CTRadioAccessTechnologyCDMA1x":
            return "CDMA"
        case "CTRadioAccessTechnologyGPRS":
            return "GPRS"
        case "CTRadioAccessTechnologyWCDMA":
            return "WCDMA"
        case "CTRadioAccessTechnologyHSDPA":
            return "HSDPA"
        case "CTRadioAccessTechnologyHSUPA":
            return "HSUPA"
        case "CTRadioAccessTechnologyCDMAEVDORev0":
            return "EVDO_0"
        case "CTRadioAccessTechnologyCDMAEVDORevA":
            return "EVDO_A"
        case "CTRadioAccessTechnologyCDMAEVDORevB":
            return "EVDO_B"
            case "CTRadioAccessTechnologyeHRPD":
                return "HRPD"
        case "CTRadioAccessTechnologyLTE":
            return "LTE"
        case "CTRadioAccessTechnologyNRNSA":
            return "NRNSA"
            case "CTRadioAccessTechnologyNR":
                return "NR"
        default:
            return "unknown"
        }
    }
}
