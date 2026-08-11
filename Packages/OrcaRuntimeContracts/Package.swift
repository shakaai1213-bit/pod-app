// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OrcaRuntimeContracts",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "OrcaRuntimeContracts", targets: ["OrcaRuntimeContracts"]),
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
            ]
        ),
        .testTarget(
            name: "OrcaRuntimeContractsTests",
            dependencies: ["OrcaRuntimeContracts"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
