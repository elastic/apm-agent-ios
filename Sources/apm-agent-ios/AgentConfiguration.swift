import Foundation

public struct AgentConfiguration {
    @available(*, deprecated, message: "AgentConfiguration is deprecated. Use AgentConfigBuilder to generate configs.")
    public init() {
    }
    
    init(noop: Any) {
        
    }
    
    public var collectorHost = "127.0.0.1"
    public var collectorPort = 8200
    public var collectorTLS = false
    public var secretToken : String? = nil
}
