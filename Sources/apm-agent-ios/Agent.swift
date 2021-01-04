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
    
    var exporter : MultiSpanExporter
    var processor: SimpleSpanProcessor
    var group: MultiThreadedEventLoopGroup

    let autoInstrumenter: URLSessionAutoInstrumentation?
    
    private init(collectorHost host: String, collectorPort port: Int) {
        autoInstrumenter = URLSessionAutoInstrumentation(dateProvider: SystemDateProvider())
        URLSessionAutoInstrumentation.instance = autoInstrumenter
        autoInstrumenter?.swizzler.swizzle()
        print("Initializing Elastic iOS Agent.")

         group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let  b = ClientConnection.insecure(group: group)

        let e = OtlpTraceExporter(channel: b.connect(host: host,
                                                            port: port))
        
        let stdout = StdoutExporter()
        exporter = MultiSpanExporter(spanExporters: [e, stdout])
    
        processor = SimpleSpanProcessor(spanExporter: exporter)
        OpenTelemetrySDK.instance.tracerProvider.addSpanProcessor(processor)
    }
    deinit {
          try! group.syncShutdownGracefully()
    }
}
