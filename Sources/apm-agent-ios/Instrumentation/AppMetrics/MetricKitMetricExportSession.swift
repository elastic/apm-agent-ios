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

/// Coordinates MetricKit payload windows with ``MetricKitTriggeredMetricReader`` export.
/// Configured when the agent registers its meter provider; no-op if not configured.
enum MetricKitMetricExportSession {
  private static let lock = NSLock()
  private weak static var triggeredReader: MetricKitTriggeredMetricReader?

  static func configure(triggeredReader: MetricKitTriggeredMetricReader) {
    lock.lock()
    defer { lock.unlock() }
    self.triggeredReader = triggeredReader
  }

  /// Binds the next ``flushMetricKitExport()`` to ``MXMetricPayload.timeStampBegin`` / ``timeStampEnd``.
  static func prepareExportForMetricKitPayload(start: Date, end: Date) {
    lock.lock()
    let reader = triggeredReader
    lock.unlock()
    reader?.setPendingExportWindow(start: start, end: end)
  }

  static func flushMetricKitExport() {
    lock.lock()
    let reader = triggeredReader
    lock.unlock()
    _ = reader?.forceFlush()
  }
}
