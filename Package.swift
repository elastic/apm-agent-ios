// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "apm-agent-ios",
    platforms: [
        .iOS(.v11),
        .macOS(.v10_13),
        .tvOS(.v11),
        .watchOS(.v3),
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other package.
        .library(name: "iOSAgent", type: .dynamic, targets: ["iOSAgent"]),
        .library(name: "libiOSAgent", type: .static, targets: ["iOSAgent"]),

        .library(name: "NetworkStatus", type: .dynamic, targets: ["NetworkStatus"]),
        .library(name: "libNetworkStatus", type: .static, targets: ["NetworkStatus"]),
    ],
    dependencies: [
        .package(name: "opentelemetry-swift", url: "git@github.com:bryce-b/opentelemetry-swift.git", .branch("customize-span-builder")),
        .package(name: "Reachability", url: "git@github.com:ashleymills/Reachability.swift.git", .branch("master")),
    ],
    targets: [
        .target(name: "NetworkStatus",
                dependencies: ["Reachability"],
                path: "Sources/Instrumentation/NetworkInfo"),
        .target(
            name: "iOSAgent",
            dependencies: [
                .product(name: "libOpenTelemetryProtocolExporter", package: "opentelemetry-swift"),
                .product(name: "libURLSessionInstrumentation", package: "opentelemetry-swift"),
                .product(name: "libResourceExtension", package: "opentelemetry-swift"),
                .product(name: "Reachability", package: "Reachability"),
                "NetworkStatus"
            ],
            path: "Sources/apm-agent-ios"
        ),
        .testTarget(
            name: "apm-agent-iosTests",
            dependencies: ["iOSAgent"],
            path: "Sources/Tests/apm-agent-iosTests"),
        .testTarget(name: "network-status-tests",
                    dependencies: ["NetworkStatus"],
                    path: "Sources/Tests/network-status-tests")
    ]
)
