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
    var group: MultiThreadedEventLoopGroup
    var channel : ClientConnection

    var memorySampler : MemorySampler
    var cpuSampler : CPUSampler
    #if os(iOS)
    var vcInstrumentation : ViewControllerInstrumentation?
    #endif
    
    var urlSessionInstrumentation : URLSessionInstrumentation?
    
    var netstatInjector : NetworkStatusInjector?
    
    private init(configuration: AgentConfiguration) {
        self.configuration = configuration
        _ = OpenTelemetrySDK.instance // initialize sdk, or else it will over write our meter provider
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    
        if configuration.collectorTLS {
            channel = ClientConnection.secure(group: group)
                .connect(host: configuration.collectorHost, port: configuration.collectorPort)
        } else {
            channel = ClientConnection.insecure(group: group)
                .connect(host: configuration.collectorHost, port: configuration.collectorPort)
        }
        
        
        Agent.initializeMetrics(grpcClient: channel)
        Agent.initializeTracing(grpcClient: channel)
              
        memorySampler = MemorySampler()
        cpuSampler = CPUSampler()
        print("Initializing Elastic iOS Agent.")
    }
    
    
    
    private func initialize() {
        initializeNetworkInstrumentation()
    }
    
    private func initializeNetworkInstrumentation() {
        do {
            let netstats = try NetworkStatus()
            self.netstatInjector = NetworkStatusInjector(netstat: netstats)
        } catch {
            print ("failed to initialize network connection status \(error)")
        }
        
        
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
                                                                    if let injector = self.netstatInjector {
                                                                        injector.inject(span: span)
                                                                    }
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

    private static func initializeMetrics(grpcClient: ClientConnection) {
        _ = OpenTelemetry.instance
        
        OpenTelemetry.registerMeterProvider(meterProvider:MeterProviderSdk(metricProcessor: MetricProcessorSdk(),
                                                                           metricExporter: OtelpMetricExporter(channel: grpcClient), metricPushInterval: MeterProviderSdk.defaultPushInterval, resource: AgentResource.get()))
    }
    
    static private func initializeTracing(grpcClient: ClientConnection) {
        let e = ElasticExporter(channel: grpcClient)

        let stdout = StdoutExporter()
        let mse = MultiSpanExporter(spanExporters: [e, stdout])

        let b = BatchSpanProcessor(spanExporter: mse)
        
        let tracerProvider = TracerProviderSdk(clock: MillisClock(), idGenerator: RandomIdGenerator(), resource: AgentResource.get())
        OpenTelemetry.registerTracerProvider(tracerProvider: tracerProvider)
        OpenTelemetrySDK.instance.tracerProvider.addSpanProcessor(b)
    }
    
    
    @objc func appEnteredBackground() {
    }
}
