import OpenTelemetryApi
import OpenTelemetrySdk
import ResourceExtension
import OpenTelemetryProtocolExporter
import Foundation
import URLSessionInstrumentation
import Reachability
import NetworkStatus
import CPUSampler
import MemorySampler
import GRPC
import NIO
import Logging
#if os(iOS)
import UIKit
#endif
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
        return instance
    }

    var configuration : AgentConfiguration
    var otlpConfiguration : OtlpConfiguration
    var group: MultiThreadedEventLoopGroup
    var channel : ClientConnection

    var memorySampler : MemorySampler
    var cpuSampler : CPUSampler
    
    #if os(iOS)
    var vcInstrumentation : ViewControllerInstrumentation?
    #endif
    
    var urlSessionInstrumentation : URLSessionInstrumentation?
    
    #if os(iOS)
    var netstatInjector : NetworkStatusInjector?
    #endif
    
    private init(configuration: AgentConfiguration) {
        self.configuration = configuration
        _ = OpenTelemetrySDK.instance // initialize sdk, or else it will over write our providers
        _ = OpenTelemetry.instance    // initialize api, or else it will over write our providers

        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        
        otlpConfiguration = OtlpConfiguration(timeout:OtlpConfiguration.DefaultTimeoutInterval,headers: Self.generateMetadata(configuration.secretToken))
    
        if configuration.collectorTLS {
            channel = ClientConnection.secure(group: group)
                .connect(host: configuration.collectorHost, port: configuration.collectorPort)
        } else {
            channel = ClientConnection.insecure(group: group)
                .connect(host: configuration.collectorHost, port: configuration.collectorPort)
        }

        
        // create meter provider
        OpenTelemetry.registerMeterProvider(meterProvider:MeterProviderBuilder()
                                                .with(resource: AgentResource.get())
                                                .with(exporter: OtlpMetricExporter(channel: channel, config:otlpConfiguration))
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
        
        OpenTelemetry.registerTracerProvider(tracerProvider: TracerProviderBuilder()
                                                .add(spanProcessor: b)
                                                .with(resource: AgentResource.get())
                                                .build())
                      
        memorySampler = MemorySampler()
        cpuSampler = CPUSampler()
        print("Initializing Elastic iOS Agent.")
    }
    
    
    
    private func initialize() {
        initializeNetworkInstrumentation()
    }
    
    private func initializeNetworkInstrumentation() {
        #if os(iOS)
        do {
            let netstats = try NetworkStatus()
            self.netstatInjector = NetworkStatusInjector(netstat: netstats)
        } catch {
            print ("failed to initialize network connection status \(error)")
        }
        #endif
        
        let config = URLSessionInstrumentationConfiguration.init(shouldRecordPayload: nil,
                                                                 shouldInstrument: nil,
                                                                 nameSpan:{ request in
                                                                    if let host = request.url?.host, let method = request.httpMethod {
                                                                        return "\(method) \(host)"
                                                                    }
                                                                   return nil
                                                                 } ,
                                                                 shouldInjectTracingHeaders: nil,
                                                                 createdRequest: { (request, span) in
                                                                    #if os(iOS)
                                                                    if let injector = self.netstatInjector {
                                                                        injector.inject(span: span)
                                                                    }
                                                                    #endif
                                                                },
                                                                 receivedResponse: nil,
                                                                 receivedError: { (error, dataOrFile, status, span) in
                                                                    span.addEvent(name: SemanticAttributes.exception.rawValue,
                                                                                  attributes: [SemanticAttributes.exceptionType.rawValue : AttributeValue.string(String(describing: type(of:error))),
                                                                                               SemanticAttributes.exceptionEscaped.rawValue: AttributeValue.bool(false),
                                                                                               SemanticAttributes.exceptionMessage.rawValue: AttributeValue.string(error.localizedDescription)])
                                                                })
        

        
        urlSessionInstrumentation = URLSessionInstrumentation(configuration: config)
    }

    
    deinit {
          try! group.syncShutdownGracefully()
    }

        
    static private func generateMetadata(_ token: String?) -> [(String,String)]? {
        if let t = token {
            return [("Authorization", "Bearer \(t)")]
        }
        return nil
    }
    
    @objc func appEnteredBackground() {
    }
}
