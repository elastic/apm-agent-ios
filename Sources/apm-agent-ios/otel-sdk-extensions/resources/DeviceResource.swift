import Foundation
import UIKit
import OpenTelemetryApi
import OpenTelemetrySdk

public enum DeviceResourceConstants : String {
    case osType = "os.type"
    case osVersion = "os.version"
    case deviceModel = "device.model.id"
    case deviceModelName = "device.model.name"
}

class DeviceResource : ResourceProvider {
    override var attributes: [String : AttributeValue] {
        return [
            DeviceResourceConstants.osType.rawValue: AttributeValue.string(UIDevice.current.systemName),
            DeviceResourceConstants.osVersion.rawValue: AttributeValue.string("semver:\(UIDevice.current.systemVersion)"),
            DeviceResourceConstants.deviceModel.rawValue: AttributeValue.string(UIDevice.current.model),
            DeviceResourceConstants.deviceModelName.rawValue: AttributeValue.string(UIDevice.current.localizedModel)
        ]
    }
}
z
