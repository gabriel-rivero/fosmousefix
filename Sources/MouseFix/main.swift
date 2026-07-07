import CoreGraphics
import Foundation
import MouseFixCore

let installPath = "/usr/local/bin/mousefix"
let launchAgentLabel = "com.mousefix.daemon"
let launchAgentPlist = NSHomeDirectory() + "/Library/LaunchAgents/\(launchAgentLabel).plist"

func eprint(_ items: Any..., terminator: String = "\n") {
    let msg = items.map { "\($0)" }.joined(separator: " ") + terminator
    FileHandle.standardError.write(Data(msg.utf8))
}

func printUsage() {
    let name = CommandLine.arguments.first ?? "MouseFix"
    eprint("Usage: \(name) [options]")
    eprint("")
    eprint("Options:")
    eprint("  --install              Install daemon to \(installPath) and load launch agent")
    eprint("  --uninstall            Unload launch agent and remove files")
    eprint("  --status               Check installation and accessibility status")
    eprint("  --validate             Run self-tests")
    eprint("  --listen               Print button numbers for all mouse events")
    eprint("  --config <path>        Config file path (default: ~/.config/mousefix/config.json)")
    eprint("  --verbose              Enable verbose logging")
    eprint("  --help, -h             Show this help")
}

func parseArgs() -> (configPath: String?, shouldInstall: Bool, shouldUninstall: Bool, shouldStatus: Bool, shouldValidate: Bool, shouldListen: Bool, verbose: Bool) {
    let args = CommandLine.arguments.dropFirst()
    var configPath: String?
    var shouldInstall = false
    var shouldUninstall = false
    var shouldStatus = false
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
        case "--status":
            shouldStatus = true
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
    return (configPath, shouldInstall, shouldUninstall, shouldStatus, shouldValidate, shouldListen, verbose)
}

// MARK: - Privileged execution (via osascript + admin auth dialog)

func runWithPrivileges(shellCommand: String) -> Bool {
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("mousefix-install-\(getpid()).sh")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    guard let data = "#!/bin/sh\nset -e\n\(shellCommand)\n".data(using: .utf8),
          (try? data.write(to: tempURL)) != nil,
          (try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempURL.path)) != nil
    else {
        eprint("✗ Failed to create install script")
        return false
    }

    let script = "do shell script \"\(tempURL.path)\" with administrator privileges"
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.arguments = ["-e", script]
    task.standardOutput = Pipe()
    task.standardError = Pipe()
    try? task.run()
    task.waitUntilExit()

    if task.terminationStatus != 0 {
        let errData = (task.standardError as? Pipe)?.fileHandleForReading.readDataToEndOfFile()
        let errMsg = errData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        if errMsg.contains("User canceled") || errMsg.contains("(-128)") {
            eprint("✗ Authentication cancelled")
        }
    }
    return task.terminationStatus == 0
}

// MARK: - Accessibility check

func checkAccessibility() -> Bool {
    let mask: CGEventMask = 1 << CGEventType.otherMouseDown.rawValue
    let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: mask,
        callback: { _, _, _, _ in return nil },
        userInfo: nil
    )
    if let t = tap {
        CFMachPortInvalidate(t)
        return true
    }
    return false
}

// MARK: - Install

func daemonPlistArguments() -> [String] {
    [installPath, "--verbose"]
}

func createLaunchAgentPlist() -> Bool {
    let plist: [String: Any] = [
        "Label": launchAgentLabel,
        "ProgramArguments": daemonPlistArguments(),
        "RunAtLoad": true,
        "KeepAlive": true,
        "ProcessType": "Background",
        "EnvironmentVariables": ["PATH": "/usr/local/bin:/usr/bin:/bin"],
        "StandardOutPath": NSHomeDirectory() + "/Library/Logs/MouseFix.log",
        "StandardErrorPath": NSHomeDirectory() + "/Library/Logs/MouseFix.log",
    ]

    let dir = (launchAgentPlist as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

    guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else {
        eprint("✗ Failed to create plist data")
        return false
    }
    try? data.write(to: URL(fileURLWithPath: launchAgentPlist))
    return true
}

func runLaunchCtl(_ args: [String]) -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    task.arguments = args
    try? task.run()
    task.waitUntilExit()
    return task.terminationStatus == 0
}

func copyBinary(from src: String, to dst: String) -> Bool {
    // Try direct copy first (works if user has write permission)
    let fm = FileManager.default
    try? fm.removeItem(atPath: dst)
    if fm.fileExists(atPath: dst) { return false }
    if (try? fm.copyItem(atPath: src, toPath: dst)) != nil {
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dst)
        return true
    }
    // Fall back to admin auth
    let cmd = "mkdir -p /usr/local/bin && rm -f '\(dst)' && cp '\(src)' '\(dst)' && chmod 755 '\(dst)'"
    return runWithPrivileges(shellCommand: cmd)
}

func installDaemon() {
    let selfPath = CommandLine.arguments.first!
    let resolvedPath = URL(fileURLWithPath: selfPath).resolvingSymlinksInPath().path
    eprint("Installing from: \(resolvedPath)")

    guard copyBinary(from: resolvedPath, to: installPath) else {
        eprint("✗ Failed to install binary")
        return
    }
    eprint("✓ Installed to \(installPath)")

    // Create default config if missing
    let configPath = defaultConfigPath()
    if !FileManager.default.fileExists(atPath: configPath) {
        let defaultConfig = AppConfig()
        if let data = encodeConfig(defaultConfig) {
            try? FileManager.default.createDirectory(
                atPath: (configPath as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            try? data.write(to: URL(fileURLWithPath: configPath))
            eprint("✓ Created default config at \(configPath)")
        }
    }

    // Unload existing launch agent (ignore failure — may not be loaded)
    runLaunchCtl(["unload", launchAgentPlist])
    // Small delay to ensure process exits
    Thread.sleep(forTimeInterval: 0.3)

    guard createLaunchAgentPlist() else { return }
    eprint("✓ Created launch agent plist")

    if runLaunchCtl(["load", launchAgentPlist]) {
        eprint("✓ Launch agent loaded")
    } else {
        eprint("✗ Failed to load launch agent")
    }

    // Accessibility check
    if checkAccessibility() {
        eprint("✓ Accessibility permission is granted")
    } else {
        eprint("")
        eprint("⚠  Accessibility permission is NOT granted.")
        eprint("   Open System Settings → Privacy & Security → Accessibility")
        eprint("   Add \"\(installPath)\" to the list, or check its checkbox.")
        eprint("   Then run: \(CommandLine.arguments.first ?? "mousefix") --install")
        eprint("")
        eprint("   If the app doesn't appear, click the + button and navigate to")
        eprint("   /usr/local/bin/mousefix (press Cmd+Shift+G to enter the path).")
    }
}

// MARK: - Uninstall

func uninstallDaemon() {
    // Unload launch agent
    if FileManager.default.fileExists(atPath: launchAgentPlist) {
        if runLaunchCtl(["unload", launchAgentPlist]) {
            eprint("✓ Launch agent unloaded")
        } else {
            eprint("⚠ Could not unload launch agent (may not be loaded)")
        }
        try? FileManager.default.removeItem(atPath: launchAgentPlist)
        eprint("✓ Removed launch agent plist")
    } else {
        eprint("✓ No launch agent plist found")
    }

    // Kill any running daemon process
    let killTask = Process()
    killTask.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
    killTask.arguments = ["-9", "-f", "^\(installPath)$"]
    try? killTask.run()
    killTask.waitUntilExit()

    // Remove binary (with admin auth)
    if FileManager.default.fileExists(atPath: installPath) {
        let removeCmd = "rm -f '\(installPath)'"
        if runWithPrivileges(shellCommand: removeCmd) {
            eprint("✓ Removed \(installPath)")
        } else {
            eprint("⚠ Could not remove \(installPath)")
        }
    } else {
        eprint("✓ No binary found at \(installPath)")
    }

    eprint("")
    eprint("Config file preserved at \(defaultConfigPath())")
    eprint("To remove it manually: rm \(defaultConfigPath())")
}

// MARK: - Status

func runStatus() {
    eprint("MouseFix Status")
    eprint("===============")

    // Binary
    var isInstalled = false
    if FileManager.default.fileExists(atPath: installPath) {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: installPath),
           let size = attrs[.size] as? UInt64,
           let mod = attrs[.modificationDate] as? Date {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH:mm"
            eprint("✓ Binary: \(installPath) (\(size) bytes, modified \(df.string(from: mod)))")
        } else {
            eprint("✓ Binary: \(installPath)")
        }
        isInstalled = true
    } else {
        eprint("✗ Binary: not found at \(installPath)")
    }

    // Launch agent plist
    if FileManager.default.fileExists(atPath: launchAgentPlist) {
        eprint("✓ Launch agent: \(launchAgentPlist)")
    } else {
        eprint("✗ Launch agent: not found")
    }

    // Daemon running
    let runningTask = Process()
    runningTask.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    runningTask.arguments = ["print", "gui/\(getuid())/\(launchAgentLabel)"]
    runningTask.standardOutput = Pipe()
    runningTask.standardError = Pipe()
    try? runningTask.run()
    runningTask.waitUntilExit()
    if runningTask.terminationStatus == 0 {
        eprint("✓ Daemon: running (via launch agent)")
    } else {
        // Check for any mousefix process
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-f", "[M]ouseFix"]
        pgrep.standardOutput = Pipe()
        try? pgrep.run()
        pgrep.waitUntilExit()
        if pgrep.terminationStatus == 0 {
            let data = (pgrep.standardOutput as! Pipe).fileHandleForReading.readDataToEndOfFile()
            let pids = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            eprint("✓ Daemon: running (PID \(pids))")
        } else if isInstalled {
            eprint("✗ Daemon: not running")
        }
    }

    // Accessibility
    if isInstalled {
        if checkAccessibility() {
            eprint("✓ Accessibility: granted")
        } else {
            eprint("✗ Accessibility: NOT granted")
            eprint("   Add \(installPath) in System Settings → Privacy & Security → Accessibility")
        }
    }
}

// MARK: - Validation

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

// MARK: - Listener

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

// MARK: - Main

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
        uninstallDaemon()
        return
    }

    if parsed.shouldInstall {
        installDaemon()
        return
    }

    if parsed.shouldStatus {
        runStatus()
        return
    }

    // Run as daemon
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
