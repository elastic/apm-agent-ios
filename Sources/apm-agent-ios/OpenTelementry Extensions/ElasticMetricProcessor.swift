// Copyright © 2023 Elasticsearch BV
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

public class ElasticMetricProcessor: MetricProcessor {

  private let lock: NSLock
  var metrics: [Metric]
  var filters = [SignalFilter<Metric>]()

  internal init(_ filters: [SignalFilter<Metric>] = [SignalFilter<Metric>]()) {
    self.filters = filters
    metrics = [Metric]()
    lock = NSLock()
  }

  /// Finish the current collection cycle and return the metrics it holds.
  /// This is called at the end of one collection cycle by the Controller.
  /// MetricProcessor can use this to clear its Metrics (in case of stateless).
  /// - Returns: The list of metrics from this cycle, which are to be exported.
  public func finishCollectionCycle() -> [Metric] {
    lock.lock()
    defer {
      self.metrics = [Metric]()
      lock.unlock()
    }

    guard CentralConfig().data.recording else {
      return [Metric]()
    }
    return metrics
  }

  /// Process the metric. This method is called once every collection interval.
  /// - Parameters:
  ///   - metric: the metric record.
  public func process(metric: Metric) {
    lock.lock()
    defer {
      lock.unlock()
    }

    guard CentralConfig().data.recording else {
      return
    }

    for filter in filters where !filter.shouldInclude(metric) {
      return
    }

    metrics.append(metric)
  }
}
