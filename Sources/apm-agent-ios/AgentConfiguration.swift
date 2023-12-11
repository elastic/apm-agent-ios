import Foundation
import OpenTelemetrySdk
import PersistenceExporter

public struct AgentConfiguration {
  init() {}
  public var enableAgent = true
  public var collectorHost = "127.0.0.1"
  public var collectorPort = 8200
  public var collectorTLS = false
  var auth: String?
  var sampleRate: Double = 1.0

  var spanFilters = [SignalFilter<ReadableSpan>]()
  var logFilters = [SignalFilter<ReadableLogRecord>]()
  var metricFilters = [SignalFilter<Metric>]()

  public func urlComponents() -> URLComponents {

    var components = URLComponents()

    if collectorTLS {
      components.scheme = "https"
    } else {
      components.scheme = "http"
    }

    components.host = collectorHost

    components.port = collectorPort

    return components
  }
}
