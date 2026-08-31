/*
 * Licensed to Elasticsearch B.V. under one or more contributor
 * license agreements. Elasticsearch B.V. licenses this file to you under
 * the Apache License, Version 2.0 (the "License"); you may
 * not use this file except in compliance with the License.
 */

import Foundation
import OpenTelemetryApi

/// Emits the exactly-once span, log, and metric that the E2E harness asserts in Elasticsearch.
/// There is no scenario hook and no run-id reader: the harness carries `test.run_id` through
/// `SIMCTL_CHILD_OTEL_RESOURCE_ATTRIBUTES`, and the agent picks it up from the process
/// environment on its own.
enum IntegrationTelemetry {
  private static let instrumentationScope = "co.elastic.otel.ios.integration"

  static func emitLaunchSignals() {
    emitSpan()
    emitLog()
    emitMetric()
  }

  private static func emitSpan() {
    let tracer = OpenTelemetry.instance.tracerProvider.get(
      instrumentationName: instrumentationScope)
    tracer.spanBuilder(spanName: "e2e span").startSpan().end()
  }

  private static func emitLog() {
    OpenTelemetry.instance.loggerProvider
      .loggerBuilder(instrumentationScopeName: instrumentationScope)
      .build()
      .logRecordBuilder()
      .setBody(.string("e2e log"))
      .emit()
  }

  private static func emitMetric() {
    var counter = OpenTelemetry.instance.meterProvider
      .get(name: instrumentationScope)
      .counterBuilder(name: "e2e.launches")
      .build()
    counter.add(value: 1)
  }
}
