/*
 * Licensed to Elasticsearch B.V. under one or more contributor
 * license agreements. Elasticsearch B.V. licenses this file to you under
 * the Apache License, Version 2.0 (the "License"); you may
 * not use this file except in compliance with the License.
 */

import SwiftUI

/// The app's single screen. It carries no test-only state; the app emits its telemetry from
/// `AppDelegate.application(_:didFinishLaunchingWithOptions:)` before this view ever renders.
struct IntegrationHomeView: View {
  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "checkmark.seal")
        .font(.system(size: 48))
      Text("EDOT iOS Integration Test")
        .font(.headline)
      Text("This app exists only to exercise the SDK's export path for the E2E harness.")
        .font(.footnote)
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 32)
    }
    .padding()
  }
}
