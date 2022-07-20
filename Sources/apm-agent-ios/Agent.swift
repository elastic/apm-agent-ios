import CPUSampler
import Foundation
import GRPC
import Logging
import MemorySampler
import NetworkStatus
import NIO
import OpenTelemetryApi
import OpenTelemetryProtocolExporter
import OpenTelemetrySdk
import os
import Reachability
import ResourceExtension
import URLSessionInstrumentation
#if os(iOS)
    import UIKit
#endif

import os.log
public class Agent {
    public static func start(with configuaration: AgentConfiguration) {
        instance = Agent(configuration: configuaration)
        instance?.initialize()
    }

    public static func start() {
        Agent.start(with: AgentConfiguration())
    }

    private static var instance: Agent?

    public class func shared() -> Agent? {
        instance
    }

    var configuration: AgentConfiguration
    var otlpConfiguration: OtlpConfiguration
    var group: MultiThreadedEventLoopGroup
    var channel: ClientConnection

    var memorySampler: MemorySampler
    var cpuSampler: CPUSampler

    #if os(iOS)
        var vcInstrumentation: ViewControllerInstrumentation?
        var applicationInstrumentation: UIApplicationInstrumentation?
    #endif

    var urlSessionInstrumentation: URLSessionInstrumentation?

    #if os(iOS)
        var netstatInjector: NetworkStatusInjector?
    #endif

    private init(configuration: AgentConfiguration) {
        self.configuration = configuration
        _ = OpenTelemetrySDK.instance // initialize sdk, or else it will over write our providers
        _ = OpenTelemetry.instance // initialize api, or else it will over write our providers

        #if os(iOS)
            do {
                vcInstrumentation = try ViewControllerInstrumentation()
                applicationInstrumentation = try UIApplicationInstrumentation()
            } catch {
                print("failed to initalize view controller instrumentation: \(error)")
            }
        #endif // os(iOS)
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        otlpConfiguration = OtlpConfiguration(timeout: OtlpConfiguration.DefaultTimeoutInterval, headers: Self.generateMetadata(configuration.secretToken))

        if configuration.collectorTLS {
            channel = ClientConnection.usingPlatformAppropriateTLS(for: group)
                .connect(host: configuration.collectorHost, port: configuration.collectorPort)
        } else {
            channel = ClientConnection.insecure(group: group)
                .connect(host: configuration.collectorHost, port: configuration.collectorPort)
        }

        let vars = AgentResource.get().merging(other: AgentEnvResource.resource)
        // create meter provider
        OpenTelemetry.registerMeterProvider(meterProvider: MeterProviderBuilder()
            .with(processor: MetricProcessorSdk())
            .with(resource: vars)
            .with(exporter: OtlpMetricExporter(channel: channel, config: otlpConfiguration))
            .build())

        // create tracer provider
        let e = OtlpTraceExporter(channel: channel, config: otlpConfiguration)

        let b = BatchSpanProcessor(spanExporter: e) { spanData in
            // This is for clock skew compensation
            let exportTimestamp = Date().timeIntervalSince1970.toNanoseconds
            for i in spanData.indices {
                // This is for clock skew compensation
                let newResource = spanData[i].resource.merging(other: Resource(attributes: ["telemetry.sdk.elastic_export_timestamp": AttributeValue.int(Int(exportTimestamp))]))
                _ = spanData[i].settingResource(newResource)
            }
        }
        OpenTelemetry.registerContextManager(contextManager: IOSActivityContextManager.instance)
        OpenTelemetry.registerTracerProvider(tracerProvider: TracerProviderBuilder()
            .add(spanProcessor: b)
            .with(resource: AgentResource.get().merging(other: AgentEnvResource.resource))
            .build())

        memorySampler = MemorySampler()
        cpuSampler = CPUSampler()
        os_log("Initializing Elastic iOS Agent.")
    }

    private func initialize() {
        initializeNetworkInstrumentation()
        #if os(iOS)
            vcInstrumentation?.swizzle()
            applicationInstrumentation?.swizzle()
        #endif // os(iOS)
    }

    private func initializeNetworkInstrumentation() {
        #if os(iOS)
            do {
                let netstats = try NetworkStatus()
                netstatInjector = NetworkStatusInjector(netstat: netstats)
            } catch {
                print("failed to initialize network connection status \(error)")
            }
        #endif

        let config = URLSessionInstrumentationConfiguration(shouldRecordPayload: nil,
                                                            shouldInstrument: nil,
                                                            nameSpan: { request in
                                                                if let host = request.url?.host, let method = request.httpMethod {
                                                                    return "\(method) \(host)"
                                                                }
                                                                return nil
                                                            },
                                                            shouldInjectTracingHeaders: nil,
                                                            createdRequest: { _, span in
                                                                #if os(iOS)
                                                                    if let injector = self.netstatInjector {
                                                                        injector.inject(span: span)
                                                                    }
                                                                #endif
                                                            },
                                                            receivedResponse: nil,
                                                            receivedError: { error, _, _, span in
                                                                span.addEvent(name: SemanticAttributes.exception.rawValue,
                                                                              attributes: [SemanticAttributes.exceptionType.rawValue: AttributeValue.string(String(describing: type(of: error))),
                                                                                           SemanticAttributes.exceptionEscaped.rawValue: AttributeValue.bool(false),
                                                                                           SemanticAttributes.exceptionMessage.rawValue: AttributeValue.string(error.localizedDescription)])
                                                            })

        urlSessionInstrumentation = URLSessionInstrumentation(configuration: config)
    }

    deinit {
        try! group.syncShutdownGracefully()
    }

    private static func generateMetadata(_ token: String?) -> [(String, String)]? {
        if let t = token {
            return [("Authorization", "Bearer \(t)")]
        }
        return nil
    }

    @objc func appEnteredBackground() {}
}
