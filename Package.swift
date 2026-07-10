// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PodContractChecks",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PodContracts", targets: ["PodContracts"]),
    ],
    targets: [
        .target(
            name: "PodContracts",
            path: "Sources",
            exclude: [
                "App",
                "Core",
                "Data/Local",
                "Data/Remote/APIClient.swift",
                "Data/Remote/DTOs.swift",
                "Data/Remote/Endpoints.swift",
                "Data/Remote/NotificationAction.swift",
                "Data/Remote/NotificationRouter.swift",
                "Data/Remote/PushNotificationService.swift",
                "Data/Remote/SSEClient.swift",
                "Data/Repositories/AgentRepository.swift",
                "Data/Repositories/BoardRepository.swift",
                "Data/Repositories/ChannelRepository.swift",
                "Data/Repositories/FundTradesRepository.swift",
                "Data/Repositories/ProjectRepository.swift",
                "Data/Repositories/ResearchRepository.swift",
                "Data/Repositories/StandardRepository.swift",
                "Data/Repositories/WorkbenchRepository.swift",
                "Domain/Entities/Agents.swift",
                "Domain/Entities/Chat.swift",
                "Domain/Entities/Projects.swift",
                "Presentation",
            ],
            sources: [
                "Data/Remote/FundTradesDTO.swift",
                "Data/Remote/MakerDTO.swift",
                "Data/Repositories/SystemRepository.swift",
                "Domain/Entities/Knowledge.swift",
            ]
        ),
        .testTarget(
            name: "PodContractTests",
            dependencies: ["PodContracts"],
            path: "Tests/PodContractTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
