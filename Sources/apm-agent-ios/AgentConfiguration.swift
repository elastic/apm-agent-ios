import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import PersistenceExporter


public enum AgentConnectionType {
  case grpc
  case http
}

public struct AgentConfiguration {
  init() {}
  public var enableAgent = true
  public var enableRemoteManagement = true
  public var managementUrl : URL?
  public var collectorHost = "127.0.0.1"
  public var collectorPath = ""
  public var collectorPort = 8200
  public var collectorTLS = false
  public var connectionType : AgentConnectionType = .grpc
  var auth: String?
  var sampleRate: Double = 1.0

  var spanFilters = [SignalFilter<ReadableSpan>]()
  var logFilters = [SignalFilter<ReadableLogRecord>]()
  var metricFilters = [SignalFilter<Metric>]()

  var spanAttributeInterceptor : any Interceptor<[String:AttributeValue]> = NoopInterceptor<[String:AttributeValue]>()
  var logRecordAttributeInterceptor : any Interceptor<[String:AttributeValue]> = NoopInterceptor<[String:AttributeValue]>()

  public func managementUrlComponents() -> URLComponents {
    var components = URLComponents()
    if let managementUrl {
      components.scheme = managementUrl.scheme
      components.host = managementUrl.host
      components.path = managementUrl.path
      components.port = managementUrl.port
      return components
    } else {

      if collectorTLS {
        components.scheme = "https"
      } else {
        components.scheme = "http"
      }
      components.host = collectorHost
      components.port = collectorPort
      components.path = collectorPath + "/config/v1/agents"
      return components
    }
  }
}
