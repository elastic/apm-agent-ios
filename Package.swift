//swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "apm-agent-ios",
  platforms: [
    .iOS(.v13),
    .macOS(.v10_15),
    .tvOS(.v13),
    .watchOS(.v4),
  ],
  products: [
    // Products define the executables and libraries a package produces, and make them visible to other package.
    .library(name: "iOSAgent", type: .static, targets: ["iOSAgent"]),
    .library(name: "MemorySampler", type: .static, targets: ["MemorySampler"]),
    .library(name: "CPUSampler", type: .static, targets: ["CPUSampler"]),
  ],
  dependencies: [
    .package(url: "https://github.com/ashleymills/Reachability.swift", from: "5.1.0"),
    .package(
      url: "https://github.com/open-telemetry/opentelemetry-swift", exact: "1.7.0"),
    .package(url: "https://github.com/elastic/TrueTime.swift.git", exact: "1.0.0"),
    .package(
      url: "https://github.com/microsoft/plcrashreporter.git", .upToNextMajor(from: "1.0.0")),
  ],
  targets: [
    .target(
      name: "MemorySampler",
      dependencies: [
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift"),
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift"),
      ],
      path: "Sources/Instrumentation/MemorySampler"),
    .target(
      name: "CPUSampler",
      dependencies: [
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift"),
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift"),
      ],
      path: "Sources/Instrumentation/CPUSampler"),
    .target(
      name: "iOSAgent",
      dependencies: [
        .product(name: "OpenTelemetryProtocolExporter", package: "opentelemetry-swift"),
        .product(name: "PersistenceExporter", package: "opentelemetry-swift"),
        .product(name: "URLSessionInstrumentation", package: "opentelemetry-swift"),
        .product(name: "ResourceExtension", package: "opentelemetry-swift"),
        .product(name: "Reachability", package: "Reachability.swift"),
        .product(name: "TrueTime", package: "TrueTime.swift"),
        .product(name: "CrashReporter", package: "plcrashreporter"),
        "MemorySampler",
        "CPUSampler",
      ],
      path: "Sources/apm-agent-ios"
    ),
    .testTarget(
      name: "iOSAgentTests",
      dependencies: ["iOSAgent"],
      path: "Sources/Tests/apm-agent-iosTests"),
    .testTarget(
      name: "MemorySamplerTests",
      dependencies: ["MemorySampler"],
      path: "Sources/Tests/memory-sampler-tests"),
  ]
)
