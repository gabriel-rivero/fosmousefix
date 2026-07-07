import CoreGraphics
import Foundation
import MouseFixCore

func eprint(_ items: Any..., terminator: String = "\n") {
    let msg = items.map { "\($0)" }.joined(separator: " ") + terminator
    FileHandle.standardError.write(Data(msg.utf8))
}

func printUsage() {
    let name = CommandLine.arguments.first ?? "MouseFix"
    eprint("Usage: \(name) [--config <path>] [--install] [--uninstall] [--validate] [--listen] [--verbose]")
}

func parseArgs() -> (configPath: String?, shouldInstall: Bool, shouldUninstall: Bool, shouldValidate: Bool, shouldListen: Bool, verbose: Bool) {
    let args = CommandLine.arguments.dropFirst()
    var configPath: String?
    var shouldInstall = false
    var shouldUninstall = false
    var shouldValidate = false
    var shouldListen = false
    var verbose = false

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
        case "--listen":
            shouldListen = true
        case "--verbose":
            verbose = true
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            eprint("Unknown argument: \(arg)")
            printUsage()
            exit(1)
        }
    }
    return (configPath, shouldInstall, shouldUninstall, shouldValidate, shouldListen, verbose)
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
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    var config = AppConfig()
    eprint("✓ default config: \(config.mappings.count) mappings, smooth=\(config.smoothScrolling.enabled)")

    config.smoothScrolling.intensity = 0.5
    config.mappings.append(.init(button: 6, trigger: "click", action: .system("screenshot")))
    if let data = encodeConfig(config),
       let decoded = try? decoder.decode(AppConfig.self, from: data) {
        eprint("✓ config round-trip: \(decoded.mappings.count) mappings, intensity=\(decoded.smoothScrolling.intensity)")
    } else {
        eprint("✗ config round-trip failed"); ok = false
    }

    let testJSON = """
    {"smooth_scrolling":{"enabled":true,"intensity":0.3},"scroll_direction":{"flip_vertical":false},"mappings":[{"button":4,"trigger":"click","action":"back"}]}
    """
    if let data = testJSON.data(using: .utf8),
       let parsed = try? decoder.decode(AppConfig.self, from: data) {
        eprint("✓ config parse: intensity=\(parsed.smoothScrolling.intensity), mappings=\(parsed.mappings.count)")
    } else {
        eprint("✗ config parse failed"); ok = false
    }

    let minimalJSON = """
    {"mappings":[{"button":5,"trigger":"click","action":"forward"}]}
    """
    if let data = minimalJSON.data(using: .utf8),
       let parsed = try? decoder.decode(AppConfig.self, from: data) {
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

func runListener() {
    var mask: CGEventMask = 0
    mask |= (1 << CGEventType.otherMouseDown.rawValue)
    mask |= (1 << CGEventType.otherMouseUp.rawValue)
    mask |= (1 << CGEventType.leftMouseDown.rawValue)
    mask |= (1 << CGEventType.leftMouseUp.rawValue)
    mask |= (1 << CGEventType.rightMouseDown.rawValue)
    mask |= (1 << CGEventType.rightMouseUp.rawValue)

    let callback: CGEventTapCallBack = { _, type, event, _ in
        let btn = event.getIntegerValueField(.mouseEventButtonNumber)
        let loc = event.location
        let kind: String
        switch type {
        case .leftMouseDown: kind = "down"
        case .leftMouseUp: kind = "up"
        case .rightMouseDown: kind = "down"
        case .rightMouseUp: kind = "up"
        case .otherMouseDown: kind = "down"
        case .otherMouseUp: kind = "up"
        default: kind = "?"
        }
        eprint("button=\(btn) \(kind)  x=\(Int(loc.x)) y=\(Int(loc.y))")
        return Unmanaged.passUnretained(event)
    }

    guard let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: mask,
        callback: callback,
        userInfo: nil
    ) else {
        eprint("Failed to create event tap. Grant Accessibility permission.")
        exit(1)
    }

    let rls = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)

    eprint("Listening for mouse button events. Press buttons to see their numbers.")
    eprint("Press Ctrl+C to stop.")
    signal(SIGINT) { _ in exit(0) }
    signal(SIGTERM) { _ in exit(0) }
    CFRunLoopRun()
}

func main() {
    let parsed = parseArgs()

    if parsed.verbose {
        verboseEnabled = true
    }

    if parsed.shouldListen {
        runListener()
        return
    }

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
    if verboseEnabled { eprint("Verbose logging enabled") }
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
