// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "apm-agent-ios",
    platforms:  [
        .iOS(.v11),
        .macOS(.v10_13),
        .tvOS(.v11),
        .watchOS(.v3)
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other package.
        .library(name: "iOSAgent", type: .dynamic, targets: ["iOSAgent"]),
        .library(name: "libiOSAgent", type: .static, targets: ["iOSAgent"])
    ],
    dependencies: [
        .package(name: "opentelemetry-swift", url: "git@github.com:bryce-b/opentelemetry-swift.git", .branch("bryce/trace-constants")),
    ],
    targets: [
        .target(
            name: "iOSAgent",
            dependencies: [
                .product(name: "OpenTelemetryProtocolExporter", package: "opentelemetry-swift"),
            ],
            path: "Sources/apm-agent-ios"),
        .testTarget(
            name: "apm-agent-iosTests",
            dependencies: ["iOSAgent"],
            path: "Tests/apm-agent-iosTests"),
    ]
)
