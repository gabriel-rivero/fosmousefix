import SwiftUI
import MouseFixCore

@main
struct MouseFixApp: App {
    @State private var config = loadConfig()
    @State private var daemonStatus = DaemonStatus.check()

    var body: some Scene {
        Window("MouseFix Preferences", id: "prefs") {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        daemonSection
                        scrollSection
                        directionSection
                        mappingSection
                    }
                    .padding(20)
                }
                Divider()
                HStack {
                    Text("~/.config/mousefix/config.json")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Save & Apply") { save() }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .frame(width: 620, height: 620)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in
                config = loadConfig()
                daemonStatus = DaemonStatus.check()
            }
        }
    }

    // MARK: - Daemon

    private var daemonSection: some View {
        GroupBox("Daemon") {
            HStack {
                Image(systemName: daemonStatus.icon)
                    .foregroundStyle(daemonStatus.color)
                Text(daemonStatus.label)
                    .font(.caption)
                Spacer()
                if !daemonStatus.installed {
                    Button("Install Daemon") { installDaemon() }
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)
                } else {
                    Button("Uninstall") { uninstallDaemon() }
                        .buttonStyle(.bordered)
                        .tint(.red)
                }
            }
            .padding(8)
        }
    }

    private func daemonBinaryPath() -> URL? {
        // Prefer bundled daemon inside the .app bundle
        if let bundled = Bundle.main.url(forResource: "daemon", withExtension: nil) {
            return bundled
        }
        // Fall back to known build paths
        var candidates: [String] = [
            "/usr/local/bin/mousefix",
            NSHomeDirectory() + "/bin/mousefix",
        ]
        if let firstArg = CommandLine.arguments.first {
            let siblingPath = URL(fileURLWithPath: firstArg).deletingLastPathComponent().appendingPathComponent("MouseFix").path
            candidates.append(siblingPath)
        }
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    private func installDaemon() {
        guard let daemonURL = daemonBinaryPath() else {
            let alert = NSAlert()
            alert.messageText = "Daemon binary not found"
            alert.informativeText = "Build the project first with: swift build -c release"
            alert.runModal()
            return
        }

        let daemonPath = daemonURL.path
        let installPath = "/usr/local/bin/mousefix"
        let configPath = defaultConfigPath()

        // Copy: try direct first, fall back to admin osascript
        let fm = FileManager.default
        try? fm.removeItem(atPath: installPath)
        var copied = false
        if (try? fm.copyItem(atPath: daemonPath, toPath: installPath)) != nil {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installPath)
            copied = true
        } else {
            let script = """
            do shell script "mkdir -p /usr/local/bin && rm -f '\(installPath)' && cp '\(daemonPath)' '\(installPath)' && chmod 755 '\(installPath)'" with administrator privileges
            """
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", script]
            try? task.run()
            task.waitUntilExit()
            copied = task.terminationStatus == 0
        }

        guard copied else {
            let alert = NSAlert()
            alert.messageText = "Installation failed"
            alert.informativeText = "Could not copy the daemon binary."
            alert.runModal()
            return
        }

        // Create default config if missing
        if !fm.fileExists(atPath: configPath) {
            if let data = encodeConfig(config) {
                try? fm.createDirectory(atPath: (configPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                try? data.write(to: URL(fileURLWithPath: configPath))
            }
        }

        // Create launch agent plist
        let agentLabel = "com.mousefix.daemon"
        let plistPath = NSHomeDirectory() + "/Library/LaunchAgents/\(agentLabel).plist"
        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": [installPath, "--verbose"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Background",
            "EnvironmentVariables": ["PATH": "/usr/local/bin:/usr/bin:/bin"],
            "StandardOutPath": NSHomeDirectory() + "/Library/Logs/MouseFix.log",
            "StandardErrorPath": NSHomeDirectory() + "/Library/Logs/MouseFix.log",
        ]
        try? fm.createDirectory(atPath: (plistPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
            try? data.write(to: URL(fileURLWithPath: plistPath))
        }

        // Load launch agent
        let loadTask = Process()
        loadTask.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        loadTask.arguments = ["load", plistPath]
        try? loadTask.run()
        loadTask.waitUntilExit()

        daemonStatus = DaemonStatus.check()

        // Check accessibility
        if !checkAccessibility() {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "Open System Settings → Privacy & Security → Accessibility and add \(installPath)"
            alert.runModal()
        }
    }

    private func uninstallDaemon() {
        let installPath = "/usr/local/bin/mousefix"
        let agentLabel = "com.mousefix.daemon"
        let plistPath = NSHomeDirectory() + "/Library/LaunchAgents/\(agentLabel).plist"

        // Unload launch agent
        if FileManager.default.fileExists(atPath: plistPath) {
            let unloadTask = Process()
            unloadTask.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            unloadTask.arguments = ["unload", plistPath]
            try? unloadTask.run()
            unloadTask.waitUntilExit()
            try? FileManager.default.removeItem(atPath: plistPath)
        }

        // Kill daemon
        let killTask = Process()
        killTask.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killTask.arguments = ["-9", "-f", "^\(installPath)$"]
        try? killTask.run()

        // Remove binary: try direct first, fall back to admin
        try? FileManager.default.removeItem(atPath: installPath)
        if FileManager.default.fileExists(atPath: installPath) {
            let script = "do shell script \"rm -f '\(installPath)'\" with administrator privileges"
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", script]
            try? task.run()
            task.waitUntilExit()
        }

        daemonStatus = DaemonStatus.check()
    }

    // MARK: - Scrolling

    private var scrollSection: some View {
        GroupBox("Scrolling") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Smooth scrolling", isOn: $config.smoothScrolling.enabled)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Intensity: \(config.smoothScrolling.intensity, specifier: "%.1f")")
                        .font(.caption)
                    Slider(value: $config.smoothScrolling.intensity, in: 0.0...1.0, step: 0.1)
                }
                .disabled(!config.smoothScrolling.enabled)
                .padding(.leading, 20)
            }
            .padding(8)
        }
    }

    // MARK: - Direction

    private var directionSection: some View {
        GroupBox("Scroll Direction") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Flip vertical", isOn: $config.scrollDirection.flipVertical)
                Toggle("Flip horizontal", isOn: $config.scrollDirection.flipHorizontal)
            }
            .padding(8)
        }
    }

    // MARK: - Mappings

    private var mappingSection: some View {
        GroupBox("Button Mappings") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(config.mappings.enumerated()), id: \.offset) { i, mapping in
                    mappingRow(i, mapping)
                }
                Button("+ Add Mapping") {
                    config.mappings.append(.init(button: 6, trigger: "click", action: .system("mission_control")))
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(8)
        }
    }

    private func mappingRow(_ i: Int, _ m: Mapping) -> some View {
        HStack(spacing: 6) {
            TextField("Button", value: $config.mappings[i].button, format: .number)
                .frame(width: 48)
            Picker("", selection: $config.mappings[i].trigger) {
                ForEach(triggers, id: \.self) { t in Text(t).tag(t) }
            }
            .labelsHidden().frame(width: 120)
            Picker("", selection: actionKindBinding(i)) {
                ForEach(actionNames, id: \.self) { a in Text(a).tag(a) }
                Divider()
                Text("Custom Shortcut…").tag(customActionTag)
            }
            .labelsHidden().frame(width: 150)
            if case .keyCombo = m.action {
                ShortcutRecorderView(combo: comboBinding(i))
                    .frame(width: 130)
            }
            Button("−") { config.mappings.remove(at: i) }
                .buttonStyle(.borderless).foregroundStyle(.red)
        }
    }

    private let customActionTag = "__custom__"

    private func actionKindBinding(_ i: Int) -> Binding<String> {
        Binding(
            get: {
                switch config.mappings[i].action {
                case .system(let name): return name
                case .keyCombo: return customActionTag
                }
            },
            set: { newValue in
                if newValue == customActionTag {
                    if case .keyCombo = config.mappings[i].action { return }
                    config.mappings[i].action = .keyCombo(KeyCombo(keyCode: 0x7E, modifiers: ["control"]))
                } else {
                    config.mappings[i].action = .system(newValue)
                }
            }
        )
    }

    private func comboBinding(_ i: Int) -> Binding<KeyCombo> {
        Binding(
            get: {
                if case .keyCombo(let combo) = config.mappings[i].action { return combo }
                return KeyCombo(keyCode: 0x7E, modifiers: ["control"])
            },
            set: { config.mappings[i].action = .keyCombo($0) }
        )
    }

    private func save() {
        guard let data = encodeConfig(config) else { return }
        let url = URL(fileURLWithPath: defaultConfigPath())
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        task.arguments = ["-HUP", "-i", "mousefix"]
        try? task.run()
    }
}

// MARK: - Daemon Status

struct DaemonStatus {
    let installed: Bool
    let running: Bool
    let accessibilityGranted: Bool

    var label: String {
        if !installed { return "Not installed" }
        if !running { return "Installed — not running" }
        if !accessibilityGranted { return "Running — no accessibility permission" }
        return "Running"
    }

    var icon: String {
        if !installed { return "circle.slash" }
        if !running { return "exclamationmark.triangle" }
        if !accessibilityGranted { return "exclamationmark.triangle" }
        return "checkmark.circle"
    }

    var color: Color {
        if !installed { return .gray }
        if !running { return .orange }
        if !accessibilityGranted { return .orange }
        return .green
    }

    static func check() -> DaemonStatus {
        let installPath = "/usr/local/bin/mousefix"
        let installed = FileManager.default.fileExists(atPath: installPath)

        // Check running via launchctl
        var running = false
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["print", "gui/\(getuid())/com.mousefix.daemon"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
        running = task.terminationStatus == 0

        let accessibilityGranted = installed ? checkAccessibility() : false
        return DaemonStatus(installed: installed, running: running, accessibilityGranted: accessibilityGranted)
    }
}

private func checkAccessibility() -> Bool {
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

private let triggers = ["click", "double_click", "hold", "hold_scroll_up", "hold_scroll_down", "drag_up", "drag_down", "drag_left", "drag_right", "drag"]

private var actionNames: [String] {
    systemActions.keys.sorted()
}
