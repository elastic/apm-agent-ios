import Foundation

import OpenTelemetryApi
import OpenTelemetrySdk


class DeviceResourceProvider : ResourceProvider {

    let deviceSource : IDeviceDataSource
    
    init (source: IDeviceDataSource) {
        self.deviceSource = source
    }

    override var attributes: [String : AttributeValue] {
        var attributes = [String : AttributeValue]()
                
        if let deviceModel = deviceSource.model {
            // todo: update with semantic convention when it is added to the OTel sdk.
            attributes["device.model"] = AttributeValue.string(deviceModel)
        }
        
        if let deviceId = deviceSource.identifier {
            attributes[ResourceConstants.hostId.rawValue] = AttributeValue.string(deviceId)
        }
        
        return attributes
    }
}


