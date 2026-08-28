/*
 * Licensed to Elasticsearch B.V. under one or more contributor
 * license agreements. Elasticsearch B.V. licenses this file to you under
 * the Apache License, Version 2.0 (the "License"); you may
 * not use this file except in compliance with the License.
 */

import ElasticApm
import OpenTelemetryApi
import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    // The harness (`.github/scripts/e2e-test/e2e_test.sh`) runs the Elastic Agent OTLP endpoint
    // on the simulator host's loopback address.
    let agentConfiguration = AgentConfigBuilder()
      .withExportUrl(URL(string: "http://127.0.0.1:4318")!)
      .withRemoteManagement(false)
      .build()

    ElasticApmAgent.start(with: agentConfiguration)
    IntegrationTelemetry.emitLaunchSignals()

    return true
  }
}

@main
struct IntegrationTestApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    WindowGroup {
      IntegrationHomeView()
    }
  }
}
