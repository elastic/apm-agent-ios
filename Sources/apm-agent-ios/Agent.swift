import OpenTelemetryApi
import OpenTelemetrySdk
import OpenTelemetryProtocolExporter
import Foundation
//import StdoutExporter
import GRPC
import NIO
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
    var metricChannel : ClientConnection
    var traceChannel : ClientConnection

    
    private init(collectorHost host: String, collectorPort port: Int) {
        _ = OpenTelemetrySDK.instance // intialize sdk, or else it will over write our meter provider
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        metricChannel = ClientConnection.insecure(group: group).connect(host: host, port: port)
        traceChannel = ClientConnection.insecure(group: group).connect(host: host, port: port)
        Agent.initializeMetrics(grpcClient: metricChannel)
        Agent.initializeTracing(grpcClient: traceChannel)
        
        print("Initializing Elastic iOS Agent.")
    }
    deinit {
          try! group.syncShutdownGracefully()
    }
    
    static private func initializeMetrics(grpcClient: ClientConnection) {
        _ = OpenTelemetry.instance
        OpenTelemetry.registerMeterProvider(meterProvider: MeterSdkProvider(metricProcessor: MetricSdkProcessor(), metricExporter: OtelpMetricExporter(channel:grpcClient)))

    }
    static private func initializeTracing(grpcClient: ClientConnection) {
        let e = OtlpTraceExporter(channel: grpcClient)
        
        let stdout = StdoutExporter()
        let mse = MultiSpanExporter(spanExporters: [e, stdout])
    
        let p = SimpleSpanProcessor(spanExporter: mse)
        let tracerProvider = TracerSdkProvider(clock: MillisClock(), idGenerator: RandomIdGenerator(), resource: DeviceResource().create())
        OpenTelemetry.registerTracerProvider(tracerProvider: tracerProvider)
        OpenTelemetrySDK.instance.tracerProvider.addSpanProcessor(p)
    }
}
