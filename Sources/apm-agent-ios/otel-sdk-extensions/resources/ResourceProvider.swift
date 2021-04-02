import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

class ResourceProvider {
    var attributes: [String: AttributeValue] {
        return [String: AttributeValue]()
    }

    public func create() -> Resource {
        return Resource(attributes: attributes)
    }
}
