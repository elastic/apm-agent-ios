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
    .library(name: "ElasticApm", type: .static, targets: ["ElasticApm"]),
    .library(name: "MemorySampler", type: .static, targets: ["MemorySampler"]),
    .library(name: "CPUSampler", type: .static, targets: ["CPUSampler"]),
  ],
  dependencies: [
    .package(url: "https://github.com/ashleymills/Reachability.swift", from: "5.2.4"),
    .package(
      url: "https://github.com/open-telemetry/opentelemetry-swift", exact: "1.12.1"),
    .package(url: "https://github.com/MobileNativeFoundation/Kronos.git", .upToNextMajor(from: "4.2.2")),
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
      name: "ElasticApm",
      dependencies: [
        .product(name: "OpenTelemetryProtocolExporter", package: "opentelemetry-swift"),
        .product(name: "OpenTelemetryProtocolExporterHTTP", package: "opentelemetry-swift"),
        .product(name: "PersistenceExporter", package: "opentelemetry-swift"),
        .product(name: "URLSessionInstrumentation", package: "opentelemetry-swift"),
        .product(name: "ResourceExtension", package: "opentelemetry-swift"),
        .product(name: "Reachability", package: "Reachability.swift"),
        .product(name: "Kronos", package: "Kronos"),
        .product(name: "CrashReporter", package: "plcrashreporter"),
        "MemorySampler",
        "CPUSampler",
      ],
      path: "Sources/apm-agent-ios",
      resources: [
        .process("Resources/PrivacyInfo.xcprivacy")
      ]
//      plugins: [.plugin(name: "SwiftLintPlugin", package:"SwiftLint")]
    ),
    .testTarget(
      name: "ElasticApmTests",
      dependencies: ["ElasticApm"],
      path: "Sources/Tests/apm-agent-iosTests"),
    .testTarget(
      name: "MemorySamplerTests",
      dependencies: ["MemorySampler"],
      path: "Sources/Tests/memory-sampler-tests"),
  ]
)
