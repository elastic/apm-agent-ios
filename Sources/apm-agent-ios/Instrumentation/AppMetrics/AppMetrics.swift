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
import MetricKit
import OpenTelemetryApi
import OpenTelemetrySdk
public extension Meter {
    func addMetric(name: String, type: AggregationType, data: [MetricData]) {
        //noop
    }
}

@available(iOS 13.0, *)
class AppMetrics : NSObject, MXMetricManagerSubscriber {
    
    let meter = OpenTelemetrySDK.instance.meterProvider.get(instrumentationName: "ApplicationMetrics", instrumentationVersion: "0.0.1") 
    
    func receiveReports() {
       let shared = MXMetricManager.shared
       shared.add(self)
    }

    func pauseReports() {
       let shared = MXMetricManager.shared
       shared.remove(self)
    }

    // Receive daily metrics.
    func didReceive(_ payloads: [MXMetricPayload]) {
       // Process metrics.
        
        for metric in payloads {
            if let timeToFirstDrawEnumerator = metric.applicationLaunchMetrics?.histogrammedTimeToFirstDraw.bucketEnumerator {
        
            
            let rawHistogram = meter.createRawDoubleHistogram(name: "application.launch.time")
            var bounds = [Double]()
            var counts = [Int]()
            var sum = 0.0
            var count = 0
            for bucket in timeToFirstDrawEnumerator.allObjects as! [MXHistogramBucket]{
                bounds.append(bucket.bucketStart.value)
                bounds.append(bucket.bucketEnd.value)
                counts.append(0)
                counts.append(bucket.bucketCount)
                let avg = (bucket.bucketStart.value + bucket.bucketEnd.value) / 2
                sum += avg * Double(bucket.bucketCount)
                count += bucket.bucketCount
            }
            counts.append(0)
            
//            SummaryData
                rawHistogram.record(explicitBoundaries: bounds, counts: counts, startDate: metric.timeStampBegin, endDate: metric.timeStampEnd, count: count, sum: sum, labels: ["type": "first draw"])

            }
            if let resumeTimeEnumerator = metric.applicationLaunchMetrics?.histogrammedApplicationResumeTime.bucketEnumerator {
                let rawHistogram = meter.createRawDoubleHistogram(name: "application.launch.time")
    
                var bounds = [Double]()
                var counts = [Int]()
                var sum = 0.0
                var count = 0
                for bucket in resumeTimeEnumerator.allObjects as! [MXHistogramBucket]{
                    bounds.append(bucket.bucketStart.value)
                    bounds.append(bucket.bucketEnd.value)
                    counts.append(0)
                    counts.append(bucket.bucketCount)
                    let avg = (bucket.bucketStart.value + bucket.bucketEnd.value) / 2
                    sum += avg * Double(bucket.bucketCount)
                    count += bucket.bucketCount
                }
                counts.append(0)
                
    //            SummaryData
                rawHistogram.record(explicitBoundaries: bounds, counts: counts, startDate: metric.timeStampBegin, endDate: metric.timeStampEnd, count: count, sum: sum, labels: ["type": "resume"])
            }
            
            if #available(iOS 15.2, *) {
                if let optimizedTimeToFirstDraw = metric.applicationLaunchMetrics?.histogrammedOptimizedTimeToFirstDraw.bucketEnumerator {
                let rawHistogram = meter.createRawDoubleHistogram(name: "application.launch.time")
                var bounds = [Double]()
                var counts = [Int]()
                var sum = 0.0
                var count = 0
                for bucket in optimizedTimeToFirstDraw.allObjects as! [MXHistogramBucket]{
                    bounds.append(bucket.bucketStart.value)
                    bounds.append(bucket.bucketEnd.value)
                    counts.append(0)
                    counts.append(bucket.bucketCount)
                    let avg = (bucket.bucketStart.value + bucket.bucketEnd.value) / 2
                    sum += avg * Double(bucket.bucketCount)
                    count += bucket.bucketCount
                }
                counts.append(0)
                
                    rawHistogram.record(explicitBoundaries: bounds, counts: counts, startDate: metric.timeStampBegin, endDate: metric.timeStampEnd, count: count, sum: sum, labels: ["type": "optimized first draw"])
            }
                
            }
        
            if let applicationHangTime = metric.applicationResponsivenessMetrics?.histogrammedApplicationHangTime.bucketEnumerator {
                let rawHistogram = meter.createRawDoubleHistogram(name: "application.responsiveness.hangtime")
                var bounds = [Double]()
                var counts = [Int]()
                var sum = 0.0
                var count = 0
                for bucket in applicationHangTime.allObjects as! [MXHistogramBucket]{
                    bounds.append(bucket.bucketStart.value)
                    bounds.append(bucket.bucketEnd.value)
                    counts.append(0)
                    counts.append(bucket.bucketCount)
                    let avg = (bucket.bucketStart.value + bucket.bucketEnd.value) / 2
                    sum += avg * Double(bucket.bucketCount)
                    count += bucket.bucketCount
                }
                counts.append(0)
                
    //            SummaryData
                rawHistogram.record(explicitBoundaries: bounds, counts: counts, startDate: metric.timeStampBegin, endDate: metric.timeStampEnd, count: count, sum: sum, labels: [String: String]())
            }

            // add Application Exit Data metrics
            if #available(iOS 14.0, *) {
                let appExit = meter.createRawIntCounter(name: "application.exit")

                if let foregroundApplicationExit = metric.applicationExitMetrics?.foregroundExitData {
                    appExit.record(sum: foregroundApplicationExit.cumulativeMemoryResourceLimitExitCount,
                                   startDate: metric.timeStampBegin,
                                   endDate: metric.timeStampEnd,
                                   labels:["appState" : "foreground", "type" : "memoryResourceLimit"])
                    
                    appExit.record(sum: foregroundApplicationExit.cumulativeAppWatchdogExitCount,
                                   startDate: metric.timeStampBegin,
                                   endDate: metric.timeStampEnd,
                                   labels:["appState": "foreground", "type" : "watchdog"])
                    
                    appExit.record(sum: foregroundApplicationExit.cumulativeBadAccessExitCount,
                                   startDate: metric.timeStampBegin,
                                   endDate: metric.timeStampEnd,
                                   labels: ["appState": "foreground", "type" : "badAccess"])
                    
                    appExit.record(sum: foregroundApplicationExit.cumulativeAbnormalExitCount,
                                   startDate: metric.timeStampBegin,
                                   endDate: metric.timeStampEnd,
                                   labels: ["appState": "foreground", "type": "abnormal"])

                    appExit.record(sum: foregroundApplicationExit.cumulativeIllegalInstructionExitCount,
                                   startDate: metric.timeStampBegin,
                                   endDate: metric.timeStampEnd,
                                   labels:["appState":"foreground", "type": "illegalInstruction"])

                    appExit.record(sum: foregroundApplicationExit.cumulativeNormalAppExitCount,
                                   startDate: metric.timeStampBegin,
                                   endDate: metric.timeStampEnd,
                                   labels: ["appState":"foreground", "type": "normal"])
                }
                
                if let backgroundApplicationExit = metric.applicationExitMetrics?.backgroundExitData {
                    appExit.record(sum: backgroundApplicationExit.cumulativeMemoryResourceLimitExitCount,
                                   startDate: metric.timeStampBegin,
                                   endDate: metric.timeStampEnd,
                                   labels:["appState" : "background", "type": "memoryResourceLimit"])
                    
                    appExit.record(sum: backgroundApplicationExit.cumulativeAppWatchdogExitCount,
                                   startDate: metric.timeStampBegin,
                                   endDate: metric.timeStampEnd,
                                   labels:["appState": "background", "type": "watchdog"])
                    
                    appExit.record(sum: backgroundApplicationExit.cumulativeBadAccessExitCount,
                                   startDate: metric.timeStampBegin,
                                   endDate: metric.timeStampEnd,
                                   labels: ["appState": "background", "type": "badAccess"])
                    
                    appExit.record(sum: backgroundApplicationExit.cumulativeAbnormalExitCount,
                                   startDate: metric.timeStampBegin,
                                   endDate: metric.timeStampEnd,
                                   labels: ["appState": "background", "type": "abnormal"])

                    appExit.record(sum: backgroundApplicationExit.cumulativeIllegalInstructionExitCount,
                                   startDate: metric.timeStampBegin,
                                   endDate: metric.timeStampEnd,
                                   labels:["appState": "background", "type": "illegalInstruction"])

                    appExit.record(sum: backgroundApplicationExit.cumulativeNormalAppExitCount,
                                   startDate: metric.timeStampBegin,
                                   endDate: metric.timeStampEnd,
                                   labels: ["appState": "background", "type": "normal"])
                }
        
            }
        }
    }

    // Receive diagnostics immediately when available.
    @available(iOS 14.0, *)
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
       // Process diagnostics.
    }

}
