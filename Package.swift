// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenClawVox",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "OpenClawVox", targets: ["OpenClawVox"])
    ],
    targets: [
        .executableTarget(
            name: "OpenClawVox",
            path: "Sources"
        )
    ]
)
