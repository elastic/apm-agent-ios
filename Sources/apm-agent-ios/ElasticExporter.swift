// Copyright © 2021 Elasticsearch BV
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
import OpenTelemetryApi
import OpenTelemetrySdk
import OpenTelemetryProtocolExporter

public class ElasticExporter : OtlpTraceExporter {
    override open func export(spans: [SpanData]) -> SpanExporterResultCode {
        let exportTimestamp = Date().timeIntervalSince1970.toNanoseconds
        
        var newSpans = spans
        
        for index in newSpans.indices {
            let newResource = newSpans[index].resource.merging(other: Resource(attributes: ["telemetry.sdk.elastic_export_timestamp": AttributeValue.int(Int(exportTimestamp))]))
            _ = newSpans[index].settingResource(newResource)
        }
        
        return super.export(spans: newSpans)
    }
}





