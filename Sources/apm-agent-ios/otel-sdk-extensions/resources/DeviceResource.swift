import Foundation
#if !os(macOS)
import UIKit
#endif
import OpenTelemetryApi
import OpenTelemetrySdk

public enum DeviceResourceConstants : String {
    case osType = "os.type"
    case osVersion = "os.version"
    case deviceModel = "device.model.id"
    case deviceModelName = "device.model.name"
}

class DeviceResource : ResourceProvider {
    
    func osVersion() -> String {
        return ProcessInfo.processInfo.operatingSystemVersionString
    }
    
    func deviceModel() -> String? {
        let hwName : UnsafeMutablePointer<Int32> = UnsafeMutablePointer<Int32>.allocate(capacity: 2)
        hwName[0] = CTL_HW
        hwName[1] = HW_MACHINE
        let machine : UnsafeMutablePointer<CChar> = UnsafeMutablePointer<CChar>.allocate(capacity: 255)
        let len : UnsafeMutablePointer<Int>! = UnsafeMutablePointer<Int>.allocate(capacity: 1)

        let error = sysctl(hwName, 2, machine, len, nil, 0)
        if error != 0 {
            print("error #\(errno): \(String(describing: String(utf8String: strerror(errno))))")

            return nil
        }
        let machineName = String(cString: machine)
        return machineName
    }
    
    func applicationVersion() -> String? {
        if let mainVersion = shortBundleVersion() {
            var VersionString = ""
            VersionString.append(mainVersion)
            if let buildNumber = bundleVersion() {
                VersionString.append(" (\(buildNumber))")
            }
            return VersionString
        }
        return bundleVersion()
    }
    
    func shortBundleVersion() -> String? {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }
    
    func bundleVersion() -> String? {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }
    
    func applicationName() -> String? {
        if let bundleName = Bundle.main.infoDictionary?["CFBundleName"] as? String {
            return bundleName
        }
        return nil
    }
    
    func bundleId() ->String? {
        return Bundle.main.infoDictionary?["CFBundleIdentifier"] as? String
    }
    
    func deviceId() -> String? {
        return UIDevice.current.identifierForVendor?.uuidString
    }
    
    override var attributes: [String : AttributeValue] {

        
        var attributes = [String : AttributeValue]()
        
        attributes["agent.name"] = AttributeValue.string("Swift")
        
        attributes["os.type"] = AttributeValue.string(UIDevice.current.systemName)
        
        attributes["os.description"] = AttributeValue.string("\(osVersion())")
        
        if let deviceModel = deviceModel() {
            attributes["device_model"] = AttributeValue.string(deviceModel)
        }
        
        if let bundleName = applicationName() {
            attributes[ResourceConstants.serviceName.rawValue] = AttributeValue.string(bundleName)
        }
        
        if let version = applicationVersion() {
            attributes[ResourceConstants.serviceVersion.rawValue] = AttributeValue.string(version)
        }
        
        if let bundleId = bundleId() {
            attributes["mobile.application.bundleIdentifier"] = AttributeValue.string(bundleId)
        }

        if let deviceId = deviceId() {
            attributes["device.identifier"] = AttributeValue.string(deviceId)
        }
        return attributes
    }
}


