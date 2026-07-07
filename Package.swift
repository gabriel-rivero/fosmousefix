// swift-tools-version: 6.0
import PackageDescription
import Foundation

// The MouseFix executable target is only built when BUILD_DAEMON is set
// (e.g. by create-app-bundle.sh).  It is excluded from default builds so
// `swift build -c release` only produces the Preferences .app binary.
let buildDaemon = ProcessInfo.processInfo.environment["BUILD_DAEMON"] != nil

let package = Package(
    name: "MouseFix",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "MouseFixCore"),
        .executableTarget(name: "Preferences", dependencies: ["MouseFixCore"]),
    ] + (buildDaemon
        ? [.executableTarget(name: "MouseFix", dependencies: ["MouseFixCore"])]
        : [])
)
