import Foundation
import URLSessionInstrumentation
import Reachability
import NetworkStatus

import GRPC
import NIO
#if os(iOS)
import UIKit
#endif
public class Agent {

    public static func start(with configuaration: AgentConfiguration) {
        instance = Agent(collectorHost: configuaration.otelCollectorAddress, collectorPort: configuaration.otelCollectorPort)
    }

    public static func start() {
        Agent.start(with: AgentConfiguration())
    }

    private static var instance: Agent?

    public class func shared() -> Agent? {
        return instance
    }

    var group: MultiThreadedEventLoopGroup

    var channel : ClientConnection
    
    
    #if os(iOS)
    var vcInstrumentation : ViewControllerInstrumentation?
    var urlSessionInstrumentation : URLSessionInstrumentation
    #endif
    
    var reachability: Reachability? = nil
    var networkStatus: NetworkStats = NetworkStats()

    
    private init(collectorHost host: String, collectorPort port: Int) {
        _ = OpenTelemetrySDK.instance // intialize sdk, or else it will over write our meter provider
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        do {
            try reachability = Reachability(hostname: host)
        } catch {
            print("failed to start reachability.")
        }
        channel = ClientConnection.insecure(group: group).connect(host: host, port: port)

        Agent.initializeMetrics(grpcClient: channel)
        Agent.initializeTracing(grpcClient: channel)
//
        #if os(iOS)
        do {
            try vcInstrumentation = ViewControllerInstrumentation.init()
            vcInstrumentation?.swizzle()
        } catch  SwizzleError.TargetNotFound(let klass, let method) {
            print ("unable to instrument \(klass).\(method). Target not found.")
        } catch {
            print("Unexpected error: \(error)")
        }
        #endif
        
        let config = URLSessionConfiguration.init { (session) -> (Bool)? in
            true
        } shouldInstrument: { (request) -> (Bool)? in
            true
        } shouldInjectTracingHeaders: { (request) -> (Bool)? in
            true
        } createdRequest: { [reachability] (request, builder) in
            if let connection = reachability {
//                builder.setAttribute(key: "network.connection", value: reachability?.connection)
                
            }
            
        } receivedResponse: { (response, dataOrFile, span) in
            
        } receivedError: { (error, dataOrFile, status, span) in
            span.addEvent(name: SemanticAttributes.exception.rawValue,
                          attributes: [SemanticAttributes.exceptionType.rawValue : AttributeValue.string(String(describing: type(of:error))),
                                       SemanticAttributes.exceptionEscaped.rawValue: AttributeValue.bool(false),
                                       SemanticAttributes.exceptionMessage.rawValue: AttributeValue.string(error.localizedDescription)])
        }

        
        urlSessionInstrumentation = URLSessionInstrumentation(configuration: config)
        
    
        
        print("Initializing Elastic iOS Agent.")
        
//        NotificationCenter.default.addObserver(self, selector: #selector(appEnteredBackground), name: UIApplication.willResignActiveNotification, object: nil)
        
    }

    deinit {
        try! group.syncShutdownGracefully()
    }

    private static func initializeMetrics(grpcClient: ClientConnection) {
        _ = OpenTelemetry.instance
        OpenTelemetry.registerMeterProvider(meterProvider: MeterProviderSdk(metricProcessor: MetricProcessorSdk(), metricExporter: OtelpMetricExporter(channel:grpcClient)))
    }   
    static private func initializeTracing(grpcClient: ClientConnection) {
        let e = OtlpTraceExporter(channel: grpcClient)

        let stdout = StdoutExporter()
        let mse = MultiSpanExporter(spanExporters: [e, stdout])

        let p = SimpleSpanProcessor(spanExporter: mse)
        let b = BatchSpanProcessor(spanExporter: mse)
        let tracerProvider = TracerProviderSdk(clock: MillisClock(), idGenerator: RandomIdGenerator(), resource: Resource())
        OpenTelemetry.registerTracerProvider(tracerProvider: tracerProvider)
        OpenTelemetrySDK.instance.tracerProvider.addSpanProcessor(b)
    }
    
    
    @objc func appEnteredBackground() {
//        if let activeSpan = OpenTelemetryContext.activeSpan {
//            activeSpan.end()
//        }
    }
}
