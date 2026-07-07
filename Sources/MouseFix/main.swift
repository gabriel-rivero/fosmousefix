import CoreGraphics
import Foundation

func eprint(_ items: Any..., terminator: String = "\n") {
    let msg = items.map { "\($0)" }.joined(separator: " ") + terminator
    FileHandle.standardError.write(Data(msg.utf8))
}

func printUsage() {
    let name = CommandLine.arguments.first ?? "MouseFix"
    eprint("Usage: \(name) [--config <path>] [--install] [--uninstall] [--validate]")
}

func parseArgs() -> (configPath: String?, shouldInstall: Bool, shouldUninstall: Bool, shouldValidate: Bool) {
    let args = CommandLine.arguments.dropFirst()
    var configPath: String?
    var shouldInstall = false
    var shouldUninstall = false
    var shouldValidate = false

    var it = args.makeIterator()
    while let arg = it.next() {
        switch arg {
        case "--config":
            configPath = it.next()
        case "--install":
            shouldInstall = true
        case "--uninstall":
            shouldUninstall = true
        case "--validate":
            shouldValidate = true
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            eprint("Unknown argument: \(arg)")
            printUsage()
            exit(1)
        }
    }
    return (configPath, shouldInstall, shouldUninstall, shouldValidate)
}

func installLaunchAgent() {
    let plistPath = NSHomeDirectory() + "/Library/LaunchAgents/com.mousefix.daemon.plist"
    let binaryPath = CommandLine.arguments.first ?? "/usr/local/bin/mousefix"

    let plist: [String: Any] = [
        "Label": "com.mousefix.daemon",
        "ProgramArguments": [binaryPath],
        "RunAtLoad": true,
        "KeepAlive": true,
        "ProcessType": "Background",
        "EnvironmentVariables": ["PATH": "/usr/local/bin:/usr/bin:/bin"],
    ]

    let dir = (plistPath as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

    guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else {
        eprint("Failed to create plist data")
        return
    }
    try? data.write(to: URL(fileURLWithPath: plistPath))

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    task.arguments = ["load", plistPath]
    try? task.run()
    task.waitUntilExit()

    eprint("Launch agent installed at \(plistPath)")
}

func uninstallLaunchAgent() {
    let plistPath = NSHomeDirectory() + "/Library/LaunchAgents/com.mousefix.daemon.plist"

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    task.arguments = ["unload", plistPath]
    try? task.run()
    task.waitUntilExit()

    try? FileManager.default.removeItem(atPath: plistPath)
    eprint("Launch agent removed")
}

func runValidation() -> Bool {
    var ok = true

    var config = AppConfig()
    eprint("✓ default config: \(config.mappings.count) mappings, smooth=\(config.smoothScrolling.enabled)")

    config.smoothScrolling.intensity = 0.5
    config.mappings.append(.init(button: 6, trigger: "click", action: .system("screenshot")))
    if let data = try? JSONEncoder().encode(config),
       let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
        eprint("✓ config round-trip: \(decoded.mappings.count) mappings")
    } else {
        eprint("✗ config round-trip failed"); ok = false
    }

    let testJSON = """
    {"smooth_scrolling":{"enabled":true,"intensity":0.3},"scroll_direction":{"flip_vertical":false},"mappings":[{"button":4,"trigger":"click","action":"back"}]}
    """
    if let data = testJSON.data(using: .utf8),
       let parsed = try? JSONDecoder().decode(AppConfig.self, from: data) {
        eprint("✓ config parse: intensity=\(parsed.smoothScrolling.intensity), mappings=\(parsed.mappings.count)")
    } else {
        eprint("✗ config parse failed"); ok = false
    }

    let minimalJSON = """
    {"mappings":[{"button":5,"trigger":"click","action":"forward"}]}
    """
    if let data = minimalJSON.data(using: .utf8),
       let parsed = try? JSONDecoder().decode(AppConfig.self, from: data) {
        eprint("✓ minimal config parse: smooth=\(parsed.smoothScrolling.enabled), mappings=\(parsed.mappings.count)")
    } else {
        eprint("✗ minimal config parse failed"); ok = false
    }

    let allActions: [(String, ActionDef)] = systemActions.map { ($0.key, .system($0.key)) }
    for (name, _) in allActions {
        if let (_, code) = systemActions[name] {
            if code == 0 && name != "launchpad" {
                eprint("✗ action '\(name)' has invalid keycode"); ok = false
            }
        } else {
            eprint("✗ action '\(name)' not found in map"); ok = false
        }
    }
    eprint("✓ \(systemActions.count) system actions")

    let comboDef = ActionDef.keyCombo(.init(keyCode: 0x31, modifiers: ["command"]))
    if let data = try? JSONEncoder().encode(comboDef),
       let decoded = try? JSONDecoder().decode(ActionDef.self, from: data),
       decoded == comboDef {
        eprint("✓ key combo encoding round-trip")
    } else {
        eprint("✗ key combo encoding failed"); ok = false
    }

    return ok
}

func main() {
    let parsed = parseArgs()

    if parsed.shouldValidate {
        exit(runValidation() ? 0 : 1)
    }

    if parsed.shouldUninstall {
        uninstallLaunchAgent()
        return
    }

    if parsed.shouldInstall {
        installLaunchAgent()
        return
    }

    let configPath = parsed.configPath ?? defaultConfigPath()
    let config = loadConfig(path: configPath)

    let manager = EventTapManager.shared
    guard manager.start(with: config) else {
        eprint("Failed to create event tap.")
        eprint("Grant Accessibility permission in:")
        eprint("  System Settings → Privacy & Security → Accessibility")
        exit(1)
    }

    eprint("MouseFix running (config: \(configPath))")
    eprint("Press Ctrl+C to stop.")

    signal(SIGINT) { _ in
        EventTapManager.shared.stop()
        exit(0)
    }
    signal(SIGTERM) { _ in
        EventTapManager.shared.stop()
        exit(0)
    }

    CFRunLoopRun()
}

main()
