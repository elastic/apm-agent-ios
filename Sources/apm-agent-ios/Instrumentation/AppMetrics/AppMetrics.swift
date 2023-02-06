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

#if os(iOS)
@available(iOS 13.0, *)
class AppMetrics : NSObject, MXMetricManagerSubscriber {
    static let instrumentation_name = "ApplicationMetrics"
    static let instrumentation_version = "0.0.2"
    
    struct LaunchTime {
        struct Labels {
            struct Types {
                static let key = "type"
                enum Values : String {
                    case resume = "resume"
                    case optimizedFirstDraw = "optimized first draw"
                    case firstDraw = "first draw"
                }
            }
        }
    }
    struct AppExit {
        struct Labels {
            struct Types {
                static let key = "type"
                enum Values : String {
                    case resourceLimit = "memoryResourceLimit"
                    case watchdog = "watchdog"
                    case badAccess = "badAccess"
                    case abnormal = "abnormal"
                    case illegalInstruction = "illegalInstruction"
                    case normal = "normal"
                }
            }
            
            struct States {
                
                static let key = "appState"
                enum Values : String {
                    case foreground = "foreground"
                    case background = "background"
                }
            }
        }
    }
    
    let meter = OpenTelemetry.instance.meterProvider.get(instrumentationName: instrumentation_name, instrumentationVersion: instrumentation_version)
    
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
                
                
                let rawHistogram = meter.createRawDoubleHistogram(name: ElasticMetrics.appLaunchTime.rawValue)
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
                rawHistogram.record(explicitBoundaries: bounds,
                                    counts: counts,
                                    startDate: metric.timeStampBegin,
                                    endDate: metric.timeStampEnd,
                                    count: count,
                                    sum: sum,
                                    labels: [LaunchTime.Labels.Types.key: LaunchTime.Labels.Types.Values.firstDraw.rawValue])
                
            }
            if let resumeTimeEnumerator = metric.applicationLaunchMetrics?.histogrammedApplicationResumeTime.bucketEnumerator {
                let rawHistogram = meter.createRawDoubleHistogram(name:ElasticMetrics.appLaunchTime.rawValue)
                
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
                rawHistogram.record(explicitBoundaries: bounds,
                                    counts: counts,
                                    startDate: metric.timeStampBegin,
                                    endDate: metric.timeStampEnd,
                                    count: count,
                                    sum: sum,
                                    labels: [LaunchTime.Labels.Types.key: LaunchTime.Labels.Types.Values.resume.rawValue])
            }
            
            if #available(iOS 15.2, *) {
                if let optimizedTimeToFirstDraw = metric.applicationLaunchMetrics?.histogrammedOptimizedTimeToFirstDraw.bucketEnumerator {
                    let rawHistogram = meter.createRawDoubleHistogram(name: ElasticMetrics.appLaunchTime.rawValue)
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
                    
                    rawHistogram.record(explicitBoundaries: bounds,
                                        counts: counts,
                                        startDate: metric.timeStampBegin,
                                        endDate: metric.timeStampEnd, count: count,
                                        sum: sum,
                                        labels: [LaunchTime.Labels.Types.key: LaunchTime.Labels.Types.Values.optimizedFirstDraw.rawValue])
                }
                
            }
            
            if let applicationHangTime = metric.applicationResponsivenessMetrics?.histogrammedApplicationHangTime.bucketEnumerator {
                let rawHistogram = meter.createRawDoubleHistogram(name: ElasticMetrics.appHangtime.rawValue)
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
                let appExit = meter.createRawIntCounter(name: ElasticMetrics.appExits.rawValue)
                
                if let foregroundApplicationExit = metric.applicationExitMetrics?.foregroundExitData {
                    appExit.record(sum: foregroundApplicationExit.cumulativeMemoryResourceLimitExitCount,
                                   startDate: metric.timeStampBegin,
                                   endDate: metric.timeStampEnd,
                                   labels:[AppExit.Labels.States.key : AppExit.Labels.States.Values.foreground.rawValue, AppExit.Labels.Types.key : AppExit.Labels.Types.Values.resourceLimit.rawValue])
                    
                    appExit.record(sum: foregroundApplicationExit.cumulativeAppWatchdogExitCount,
                                   startDate: metric.timeStampBegin,
                                   endDate: metric.timeStampEnd,
                                   labels:[AppExit.Labels.States.key:  AppExit.Labels.States.Values.foreground.rawValue,
                                           AppExit.Labels.Types.key  : AppExit.Labels.Types.Values.watchdog.rawValue])
                    
                    appExit.record(sum: foregroundApplicationExit.cumulativeBadAccessExitCount,
                                   startDate: metric.timeStampBegin,
                                   endDate: metric.timeStampEnd,
                                   labels: [AppExit.Labels.States.key: AppExit.Labels.States.Values.foreground.rawValue,
                                            AppExit.Labels.Types.key  : AppExit.Labels.Types.Values.badAccess.rawValue])
                    
                    appExit.record(sum: foregroundApplicationExit.cumulativeAbnormalExitCount,
                                   startDate: metric.timeStampBegin,
                                   endDate: metric.timeStampEnd,
                                   labels: [AppExit.Labels.States.key:  AppExit.Labels.States.Values.foreground.rawValue,
                                            AppExit.Labels.Types.key : AppExit.Labels.Types.Values.abnormal.rawValue])
                    
                    appExit.record(sum: foregroundApplicationExit.cumulativeIllegalInstructionExitCount,
                                   startDate: metric.timeStampBegin,
                                   endDate: metric.timeStampEnd,
                                   labels:[AppExit.Labels.States.key:  AppExit.Labels.States.Values.foreground.rawValue, AppExit.Labels.Types.key : AppExit.Labels.Types.Values.illegalInstruction.rawValue])
                    
                    appExit.record(sum: foregroundApplicationExit.cumulativeNormalAppExitCount,
                                   startDate: metric.timeStampBegin,
                                   endDate: metric.timeStampEnd,
                                   labels: [AppExit.Labels.States.key: AppExit.Labels.States.Values.foreground.rawValue,
                                            AppExit.Labels.Types.key : AppExit.Labels.Types.Values.normal.rawValue])
                }
                
                if let backgroundApplicationExit = metric.applicationExitMetrics?.backgroundExitData {
                    appExit.record(sum: backgroundApplicationExit.cumulativeMemoryResourceLimitExitCount,
                                   startDate: metric.timeStampBegin,
                                   endDate: metric.timeStampEnd,
                                   labels:[AppExit.Labels.States.key :  AppExit.Labels.States.Values.background.rawValue,
                                           AppExit.Labels.Types.key: AppExit.Labels.Types.Values.resourceLimit.rawValue])
                    
                    appExit.record(sum: backgroundApplicationExit.cumulativeAppWatchdogExitCount,
                                   startDate: metric.timeStampBegin,
                                   endDate: metric.timeStampEnd,
                                   labels:[AppExit.Labels.States.key: AppExit.Labels.States.Values.background.rawValue,
                                           AppExit.Labels.Types.key: AppExit.Labels.Types.Values.watchdog.rawValue])
                    
                    appExit.record(sum: backgroundApplicationExit.cumulativeBadAccessExitCount,
                                   startDate: metric.timeStampBegin,
                                   endDate: metric.timeStampEnd,
                                   labels: [AppExit.Labels.States.key: AppExit.Labels.States.Values.background.rawValue,
                                            AppExit.Labels.Types.key: AppExit.Labels.Types.Values.badAccess.rawValue])
                    
                    appExit.record(sum: backgroundApplicationExit.cumulativeAbnormalExitCount,
                                   startDate: metric.timeStampBegin,
                                   endDate: metric.timeStampEnd,
                                   labels: [AppExit.Labels.States.key: AppExit.Labels.States.Values.background.rawValue,
                                            AppExit.Labels.Types.key : AppExit.Labels.Types.Values.abnormal.rawValue])
                    
                    appExit.record(sum: backgroundApplicationExit.cumulativeIllegalInstructionExitCount,
                                   startDate: metric.timeStampBegin,
                                   endDate: metric.timeStampEnd,
                                   labels:[AppExit.Labels.States.key: AppExit.Labels.States.Values.background.rawValue,
                                           AppExit.Labels.Types.key : AppExit.Labels.Types.Values.illegalInstruction.rawValue])
                    
                    appExit.record(sum: backgroundApplicationExit.cumulativeNormalAppExitCount,
                                   startDate: metric.timeStampBegin,
                                   endDate: metric.timeStampEnd,
                                   labels: [AppExit.Labels.States.key: AppExit.Labels.States.Values.background.rawValue,
                                            AppExit.Labels.Types.key : AppExit.Labels.Types.Values.normal.rawValue])
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
#endif
