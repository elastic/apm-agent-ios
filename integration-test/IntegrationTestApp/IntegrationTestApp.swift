/*
 * Licensed to Elasticsearch B.V. under one or more contributor
 * license agreements. Elasticsearch B.V. licenses this file to you under
 * the Apache License, Version 2.0 (the "License"); you may
 * not use this file except in compliance with the License.
 */

import ElasticApm
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
    runEndToEndScenarioIfRequested()

    return true
  }

  private func runEndToEndScenarioIfRequested() {
    guard ProcessInfo.processInfo.environment["E2E_SCENARIO"] == "crash" else {
      return
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
      fatalError("Intentional crash from the EDOT iOS integration test app")
    }
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
