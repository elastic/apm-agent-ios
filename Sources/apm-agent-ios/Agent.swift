import Foundation
import GRPC
import NIO
import OpenTelemetryApi
import OpenTelemetryProtocolExporter
import OpenTelemetrySdk
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
    var channel: ClientConnection

    private init(collectorHost host: String, collectorPort port: Int) {
        _ = OpenTelemetrySDK.instance // intialize sdk, or else it will over write our meter provider
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        channel = ClientConnection.insecure(group: group).connect(host: host, port: port)

        Agent.initializeMetrics(grpcClient: channel)
        Agent.initializeTracing(grpcClient: channel)

        print("Initializing Elastic iOS Agent.")
    }

    deinit {
        try! group.syncShutdownGracefully()
    }

    private static func initializeMetrics(grpcClient: ClientConnection) {
        _ = OpenTelemetry.instance
        OpenTelemetry.registerMeterProvider(meterProvider: MeterSdkProvider(metricProcessor: MetricSdkProcessor(), metricExporter: OtelpMetricExporter(channel: grpcClient)))
    }

    private static func initializeTracing(grpcClient: ClientConnection) {
        let e = OtlpTraceExporter(channel: grpcClient)

        let stdout = StdoutExporter()
        let mse = MultiSpanExporter(spanExporters: [e, stdout])

        let p = SimpleSpanProcessor(spanExporter: mse)
        let tracerProvider = TracerSdkProvider(clock: MillisClock(), idGenerator: RandomIdGenerator(), resource: DefaultResources().get())
        OpenTelemetry.registerTracerProvider(tracerProvider: tracerProvider)
        OpenTelemetrySDK.instance.tracerProvider.addSpanProcessor(p)
    }
}
