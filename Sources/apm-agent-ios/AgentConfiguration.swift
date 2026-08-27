import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import PersistenceExporter

public enum AgentConnectionType: Equatable {
  case grpc
  case http
}

struct ExportEndpointResolution {
  let url: URL?
  let warning: String?
  let validationMessage: String?
}

public struct AgentConfiguration {
  static let exportEndpointValidationMessage =
    "Failed to start EDOT iOS: provide an explicit OTLP export URL with an http or https scheme and a host."
  static let deprecatedEndpointMigrationWarning =
    "Warning: collectorHost, collectorPath, collectorPort, and collectorTLS are deprecated; configure the endpoint with AgentConfigBuilder.withExportUrl(_:) instead."
  static let ignoredDeprecatedEndpointMutationWarning =
    "Warning: deprecated collector endpoint field changes were ignored because a full export URL was supplied."

  init() {}
  public var enableAgent = true
  public var enableRemoteManagement = true
  public var enableOpAMP = false
  public var managementUrl: URL?

  private var legacyCollectorHost = "127.0.0.1"
  private var legacyCollectorPath = ""
  private var legacyCollectorPort = 8200
  private var legacyCollectorTLS = false
  private var deprecatedEndpointPropertiesWereMutated = false
  private var fullExportUrl: URL?
  var resolvedExportUrl: URL?

  @available(
    *,
    deprecated,
    message: "Configure the endpoint with AgentConfigBuilder.withExportUrl(_:) instead."
  )
  public var collectorHost: String {
    get { legacyCollectorHost }
    set {
      legacyCollectorHost = newValue
      deprecatedEndpointPropertiesWereMutated = true
    }
  }

  @available(
    *,
    deprecated,
    message: "Configure the endpoint with AgentConfigBuilder.withExportUrl(_:) instead."
  )
  public var collectorPath: String {
    get { legacyCollectorPath }
    set {
      legacyCollectorPath = newValue
      deprecatedEndpointPropertiesWereMutated = true
    }
  }

  @available(
    *,
    deprecated,
    message: "Configure the endpoint with AgentConfigBuilder.withExportUrl(_:) instead."
  )
  public var collectorPort: Int {
    get { legacyCollectorPort }
    set {
      legacyCollectorPort = newValue
      deprecatedEndpointPropertiesWereMutated = true
    }
  }

  @available(
    *,
    deprecated,
    message: "Configure the endpoint with AgentConfigBuilder.withExportUrl(_:) instead."
  )
  public var collectorTLS: Bool {
    get { legacyCollectorTLS }
    set {
      legacyCollectorTLS = newValue
      deprecatedEndpointPropertiesWereMutated = true
    }
  }

  public var connectionType: AgentConnectionType = .http
  var auth: String?
  var sampleRate: Double = 1.0
  var useLegacyAttributeNames = false

  var spanFilters = [SignalFilter<ReadableSpan>]()
  var logFilters = [SignalFilter<ReadableLogRecord>]()

  var spanAttributeInterceptor: any Interceptor<[String: AttributeValue]> = NoopInterceptor<[String: AttributeValue]>()
  var logRecordAttributeInterceptor: any Interceptor<[String: AttributeValue]> = NoopInterceptor<[String: AttributeValue]>()

  mutating func setFullExportUrl(_ url: URL?) {
    fullExportUrl = url
  }

  mutating func projectFullExportUrl(_ url: URL) {
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    legacyCollectorTLS = components?.scheme?.lowercased() == "https"
    if let host = components?.host {
      legacyCollectorHost = host
    }
    if let port = components?.port {
      legacyCollectorPort = port
    } else {
      legacyCollectorPort = legacyCollectorTLS ? 443 : 80
    }
    legacyCollectorPath = components?.path ?? url.path
  }

  func resolveExportEndpoint() -> ExportEndpointResolution {
    if let fullExportUrl {
      let warning =
        deprecatedEndpointPropertiesWereMutated
        ? Self.ignoredDeprecatedEndpointMutationWarning
        : nil
      return Self.validate(fullExportUrl, warning: warning)
    }

    guard deprecatedEndpointPropertiesWereMutated else {
      return ExportEndpointResolution(
        url: nil,
        warning: nil,
        validationMessage: Self.exportEndpointValidationMessage
      )
    }

    var components = URLComponents()
    components.scheme = legacyCollectorTLS ? "https" : "http"
    components.host = legacyCollectorHost
    components.port = legacyCollectorPort
    components.path = legacyCollectorPath
    return Self.validate(
      components.url,
      warning: Self.deprecatedEndpointMigrationWarning
    )
  }

  mutating func setResolvedExportUrl(_ url: URL) {
    resolvedExportUrl = url
  }

  public func managementUrlComponents() -> URLComponents {
    if let managementUrl {
      return URLComponents(url: managementUrl, resolvingAgainstBaseURL: false)
        ?? URLComponents()
    }

    guard let exportUrl = resolvedExportUrl ?? resolveExportEndpoint().url else {
      return URLComponents()
    }

    var components = URLComponents()
    components.scheme = exportUrl.scheme
    components.host = exportUrl.host
    components.port = exportUrl.port
    let path = exportUrl.path
    components.path =
      (path.isEmpty || path == "/")
      ? "/config/v1/agents"
      : "\(path.hasSuffix("/") ? String(path.dropLast()) : path)/config/v1/agents"
    return components
  }

  private static func validate(
    _ url: URL?,
    warning: String?
  ) -> ExportEndpointResolution {
    guard
      let url,
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let scheme = components.scheme?.lowercased(),
      scheme == "http" || scheme == "https",
      let host = components.host,
      !host.isEmpty,
      components.port.map({ (1 ... 65_535).contains($0) }) ?? true
    else {
      return ExportEndpointResolution(
        url: nil,
        warning: warning,
        validationMessage: exportEndpointValidationMessage
      )
    }

    return ExportEndpointResolution(url: url, warning: warning, validationMessage: nil)
  }
}
