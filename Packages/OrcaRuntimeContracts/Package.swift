// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OrcaRuntimeContracts",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "OrcaDomain", targets: ["OrcaDomain"]),
        .library(name: "OrcaAPI", targets: ["OrcaAPI"]),
        .library(name: "OrcaRuntimeContracts", targets: ["OrcaRuntimeContracts"]),
        .library(name: "OrcaRuntime", targets: ["OrcaRuntime"]),
        .library(name: "OrcaDesign", targets: ["OrcaDesign"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-openapi-runtime",
            exact: "1.12.0"
        ),
        .package(
            url: "https://github.com/apple/swift-openapi-urlsession",
            exact: "1.3.1"
        ),
        .package(
            url: "https://github.com/apple/swift-http-types",
            exact: "1.6.0"
        ),
    ],
    targets: [
        .target(name: "OrcaDomain"),
        .target(name: "OrcaAPI"),
        .target(
            name: "OrcaRuntimeContracts",
            dependencies: [
                .product(
                    name: "OpenAPIRuntime",
                    package: "swift-openapi-runtime"
                ),
                .product(
                    name: "OpenAPIURLSession",
                    package: "swift-openapi-urlsession"
                ),
                .product(
                    name: "HTTPTypes",
                    package: "swift-http-types"
                ),
            ],
            exclude: [
                "openapi-generator-config.yaml",
                "openapi.json",
            ]
        ),
        .target(
            name: "OrcaRuntime",
            dependencies: ["OrcaDomain", "OrcaRuntimeContracts"]
        ),
        .target(
            name: "OrcaDesign",
            dependencies: ["OrcaDomain"]
        ),
        .testTarget(
            name: "OrcaFoundationTests",
            dependencies: ["OrcaAPI", "OrcaDesign", "OrcaDomain", "OrcaRuntime"]
        ),
        .testTarget(
            name: "OrcaRuntimeContractsTests",
            dependencies: ["OrcaRuntimeContracts"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
