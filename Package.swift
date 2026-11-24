// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CoreDesign",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .executableTarget(
            name: "CoreDesign",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            exclude: ["Fonts"],
            resources: [.copy("Brand")]
        )
    ]
)
