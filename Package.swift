// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MouseFix",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "MouseFixCore"),
        .executableTarget(name: "MouseFix", dependencies: ["MouseFixCore"]),
        .executableTarget(name: "Preferences", dependencies: ["MouseFixCore"]),
    ]
)
