// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LocalAIServer",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "LocalAIServer",
            targets: ["LocalAIServer"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/google-ai-edge/LiteRT-LM.git", from: "0.16.0")
    ],
    targets: [
        .target(
            name: "LocalAIServer",
            dependencies: [
                .product(name: "LiteRTLM", package: "LiteRT-LM")
            ],
            path: "LocalAIServer"
        )
    ]
)
