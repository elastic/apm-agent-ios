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
import OpenTelemetryApi
import OpenTelemetrySdk
#if !os(watchOS)
  import MetricKit
#endif

#if os(iOS)

  /// Subscribes to MetricKit daily metrics and records them on a dedicated Application Metrics meter provider.
  /// Export is driven by ``MetricKitTriggeredMetricReader`` (see ``ApplicationMetricsMeterProvider``).
  @available(iOS 13.0, *)
  class AppMetrics: NSObject, MXMetricManagerSubscriber {

    enum LaunchTimeValues: String {
      case key = "type"
      case resume
      case optimizedFirstDraw = "optimized first draw"
      case firstDraw = "first draw"
    }

    enum AppExitValues: String {
      case key = "type"
      case resourceLimit = "memoryResourceLimit"
      case watchdog
      case badAccess
      case abnormal
      case illegalInstruction
      case normal
    }

    enum AppExitStates: String {
      case key = "appState"
      case foreground
      case background
    }

    private let meterProvider: MeterProviderSdk
    private let meter: any Meter

    init(exporter: MetricExporter, resource: Resource) {
      let registration = AppMetricsMeterProvider.register(metricExporter: exporter, resource: resource)
      meterProvider = registration.meterProvider
      meter = registration.meter
      super.init()
    }

    /// One synchronous instrument each; recording uses attributes for exits / launch subtype.
    private lazy var launchTimeHistogram = (meter
      .histogramBuilder(name: ElasticMetrics.appLaunchTime.rawValue) as! DoubleHistogramMeterBuilderSdk)
      .setUnit("ms")
      .build()

    private lazy var hangHistogram = (meter
      .histogramBuilder(name: ElasticMetrics.appHangtime.rawValue) as! DoubleHistogramMeterBuilderSdk)
      .setUnit("ms")
      .build()

    @available(iOS 14.0, *)
    private lazy var appExitCounter = meter
      .counterBuilder(name: ElasticMetrics.appExits.rawValue)
      .build()

    func receiveReports() {
      let shared = MXMetricManager.shared
      shared.add(self)
    }

    func pauseReports() {
      let shared = MXMetricManager.shared
      shared.remove(self)
    }

    func recordTimeToFirstDraw(metric: MXMetricPayload) {
      guard let enumerator = metric.applicationLaunchMetrics?.histogrammedTimeToFirstDraw.bucketEnumerator else {
        return
      }
      recordMetricKitHistogram(
        bucketEnumerator: enumerator,
        histogram: launchTimeHistogram,
        attributes: [LaunchTimeValues.key.rawValue: AttributeValue.string(LaunchTimeValues.firstDraw.rawValue)]
      )
    }

    func recordResumeTime(metric: MXMetricPayload) {
      guard let enumerator = metric.applicationLaunchMetrics?.histogrammedApplicationResumeTime.bucketEnumerator else {
        return
      }
      recordMetricKitHistogram(
        bucketEnumerator: enumerator,
        histogram: launchTimeHistogram,
        attributes: [LaunchTimeValues.key.rawValue: AttributeValue.string(LaunchTimeValues.resume.rawValue)]
      )
    }

    func recordOptimizedTimeToFirstDraw(metric: MXMetricPayload) {
      if #available(iOS 15.2, *) {
        guard let enumerator = metric.applicationLaunchMetrics?
          .histogrammedOptimizedTimeToFirstDraw
          .bucketEnumerator else { return }

        recordMetricKitHistogram(
          bucketEnumerator: enumerator,
          histogram: launchTimeHistogram,
          attributes: [LaunchTimeValues.key.rawValue: AttributeValue.string(LaunchTimeValues.optimizedFirstDraw.rawValue)]
        )
      }
    }

    func recordHangTime(metric: MXMetricPayload) {
      guard let enumerator = metric.applicationResponsivenessMetrics?
        .histogrammedApplicationHangTime
        .bucketEnumerator else { return }

      recordMetricKitHistogram(
        bucketEnumerator: enumerator,
        histogram: hangHistogram,
        attributes: [:]
      )
    }

    func recordAppExitsBackground(metric: MXMetricPayload) {
      guard #available(iOS 14.0, *) else { return }

      guard let backgroundApplicationExit = metric.applicationExitMetrics?.backgroundExitData else { return }
      let counter = appExitCounter
      recordAppExitSlices(
        counter: counter,
        appState: AppExitStates.background,
        exitData: backgroundApplicationExit
      )
    }

    func recordAppExitsForeground(metric: MXMetricPayload) {
      guard #available(iOS 14.0, *) else { return }

      guard let foregroundApplicationExit = metric.applicationExitMetrics?.foregroundExitData else { return }
      let counter = appExitCounter
      recordAppExitSlices(
        counter: counter,
        appState: AppExitStates.foreground,
        exitData: foregroundApplicationExit
      )
    }

    // Receive daily metrics.

    func didReceive(_ payloads: [MXMetricPayload]) {
      // Process metrics.

      for metric in payloads {
        MetricKitMetricExportSession.prepareExportForMetricKitPayload(
          start: metric.timeStampBegin,
          end: metric.timeStampEnd
        )

        recordTimeToFirstDraw(metric: metric)

        recordResumeTime(metric: metric)

        recordOptimizedTimeToFirstDraw(metric: metric)

        recordHangTime(metric: metric)

        recordAppExitsForeground(metric: metric)

        recordAppExitsBackground(metric: metric)

        MetricKitMetricExportSession.flushMetricKitExport()
      }
    }

    /// Receive diagnostics immediately when available.
    @available(iOS 14.0, *)
    func didReceive(_: [MXDiagnosticPayload]) {
      // Process diagnostics.
    }

    /// Replays MetricKit histogram bucket counts with ``DoubleHistogram`` by emitting one sample per
    /// bucket count at that bucket's midpoint (equivalent midpoint weighting to the legacy raw histogram exporter).
    private func recordMetricKitHistogram(bucketEnumerator: NSFastEnumeration?,
                                          histogram: some DoubleHistogram,
                                          attributes: [String: AttributeValue]) {
      guard let bucketEnumerator else { return }
      // swiftlint:disable:next force_cast
      guard let buckets = (bucketEnumerator as AnyObject).allObjects as? [MXHistogramBucket] else { return }

      let edges = buckets.map {
        AppMetricsRecordingSupport.HistogramBucketEdge(
          startSeconds: $0.bucketStart.value,
          endSeconds: $0.bucketEnd.value,
          count: $0.bucketCount
        )
      }
      let sampleSeconds = AppMetricsRecordingSupport.histogramSampleValues(secondsFromBuckets: edges)

      var histogram = histogram
      if attributes.isEmpty {
        for midpoint in sampleSeconds {
          histogram.record(value: midpoint)
        }
      } else {
        for midpoint in sampleSeconds {
          histogram.record(value: midpoint, attributes: attributes)
        }
      }
    }

    @available(iOS 14.0, *)
    private func exitCounterPairs(exitData: MXForegroundExitData) -> [(typeRawValue: String, sum: Int)] {
      [
        (AppExitValues.resourceLimit.rawValue, exitData.cumulativeMemoryResourceLimitExitCount),
        (AppExitValues.watchdog.rawValue, exitData.cumulativeAppWatchdogExitCount),
        (AppExitValues.badAccess.rawValue, exitData.cumulativeBadAccessExitCount),
        (AppExitValues.abnormal.rawValue, exitData.cumulativeAbnormalExitCount),
        (AppExitValues.illegalInstruction.rawValue, exitData.cumulativeIllegalInstructionExitCount),
        (AppExitValues.normal.rawValue, exitData.cumulativeNormalAppExitCount)
      ]
    }

    @available(iOS 14.0, *)
    private func exitCounterPairs(exitData: MXBackgroundExitData) -> [(typeRawValue: String, sum: Int)] {
      [
        (AppExitValues.resourceLimit.rawValue, exitData.cumulativeMemoryResourceLimitExitCount),
        (AppExitValues.watchdog.rawValue, exitData.cumulativeAppWatchdogExitCount),
        (AppExitValues.badAccess.rawValue, exitData.cumulativeBadAccessExitCount),
        (AppExitValues.abnormal.rawValue, exitData.cumulativeAbnormalExitCount),
        (AppExitValues.illegalInstruction.rawValue, exitData.cumulativeIllegalInstructionExitCount),
        (AppExitValues.normal.rawValue, exitData.cumulativeNormalAppExitCount)
      ]
    }

    @available(iOS 14.0, *)
    private func applyExitSlices(counter: some LongCounter, appState: AppExitStates,
                                 pairs: [(typeRawValue: String, sum: Int)]) {
      var counter = counter
      for pair in AppMetricsRecordingSupport.nonZeroExitSums(byExitType: pairs) {
        counter.add(
          value: pair.sum,
          attributes: [
            AppExitStates.key.rawValue: AttributeValue.string(appState.rawValue),
            AppExitValues.key.rawValue: AttributeValue.string(pair.typeRawValue)
          ]
        )
      }
    }

    @available(iOS 14.0, *)
    private func recordAppExitSlices(counter: some LongCounter,
                                     appState: AppExitStates,
                                     exitData: MXForegroundExitData) {
      applyExitSlices(counter: counter, appState: appState, pairs: exitCounterPairs(exitData: exitData))
    }

    @available(iOS 14.0, *)
    private func recordAppExitSlices(counter: some LongCounter,
                                     appState: AppExitStates,
                                     exitData: MXBackgroundExitData) {
      applyExitSlices(counter: counter, appState: appState, pairs: exitCounterPairs(exitData: exitData))
    }
  }
#endif
