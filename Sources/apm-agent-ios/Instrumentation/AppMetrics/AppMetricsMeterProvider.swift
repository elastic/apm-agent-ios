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

/// Registers a dedicated ``MeterProvider`` for MetricKit ``AppMetrics`` using the agent's OTLP exporter.
enum AppMetricsMeterProvider {
  struct Registration {
    let meterProvider: MeterProviderSdk
    let meter: any Meter
  }

  static func register(metricExporter: MetricExporter, resource: Resource) -> Registration {
    let triggeredReader = MetricKitTriggeredMetricReader(exporter: metricExporter)
    let meterProvider = MeterProviderSdk.builder()
      .setResource(resource: resource)
      .registerView(
        selector: InstrumentSelector.builder().setInstrument(name: ".*").build(),
        view: View.builder().build()
      )
      .registerMetricReader(reader: triggeredReader)
      .build()

    MetricKitMetricExportSession.configure(triggeredReader: triggeredReader)

    let meter = meterProvider
      .meterBuilder(name: AppMetricsMeter.scopeName)
      .setInstrumentationVersion(instrumentationVersion: AppMetricsMeter.instrumentationVersion)
      .build()

    return Registration(meterProvider: meterProvider, meter: meter)
  }
}
