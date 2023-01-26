// Copyright © 2022 Elasticsearch BV
//
//   Licensed under the Apache License, Version 2.0 (the "License");
//   you may not use this file except in compliance with the License.
//   You may obtain a copy of the License at
//
//       http://www.apache.org/licenses/LICENSE-2.0
//
//   Unless required by applicable law or agreed to in writing, software
//   distributed under the License is distributed on an "AS IS" BASIS,
//   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//   See the License for the specific language governing permissions and
//   limitations under the License.

import Foundation
import URLSessionInstrumentation
import MemorySampler
import CPUSampler
import NetworkStatus
import OpenTelemetryApi


class InstrumentationWrapper {
        
    var appMetrics : Any?

    #if os(iOS)
        var vcInstrumentation: ViewControllerInstrumentation?
        var netstatInjector: NetworkStatusInjector?
    #endif

    var urlSessionInstrumentation: URLSessionInstrumentation?
    let config : InstrumentationConfiguration
    
    init(config: InstrumentationConfiguration) {
        self.config = config
        #if os(iOS)
            do {
                if self.config.enableViewControllerInstrumentation {
                    vcInstrumentation = try ViewControllerInstrumentation()
                }
            } catch {
                print("failed to initalize view controller instrumentation: \(error)")
            }
        #endif // os(iOS)
    }
    
    func initalize() {
        #if os(iOS)
        if #available(iOS 13.0, *) {
            if config.enableSystemMetrics {
                _ = MemorySampler()
                _ = CPUSampler()
            }
            if config.enableAppMetricInstrumentation {
                appMetrics = AppMetrics()
                if let metrics = appMetrics as? AppMetrics {
                   metrics.receiveReports()
               }
            }
        }
        #endif
        if config.enableURLSessionInstrumentation {
            initializeNetworkInstrumentation()
        }
        #if os(iOS)
            vcInstrumentation?.swizzle()
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
}
