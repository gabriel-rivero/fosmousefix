import SwiftUI
import MouseFixCore

@main
struct MouseFixApp: App {
    @State private var config = loadConfig()

    var body: some Scene {
        Window("MouseFix Preferences", id: "prefs") {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
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
            .frame(width: 520, height: 520)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in
                config = loadConfig()
            }
        }
    }

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

    private var directionSection: some View {
        GroupBox("Scroll Direction") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Flip vertical", isOn: $config.scrollDirection.flipVertical)
                Toggle("Flip horizontal", isOn: $config.scrollDirection.flipHorizontal)
            }
            .padding(8)
        }
    }

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
            Picker("", selection: $config.mappings[i].action) {
                ForEach(actionNames, id: \.self) { a in
                    Text(a).tag(ActionDef.system(a) as ActionDef)
                }
            }
            .labelsHidden()
            Button("−") { config.mappings.remove(at: i) }
                .buttonStyle(.borderless).foregroundStyle(.red)
        }
    }

    private func save() {
        guard let data = encodeConfig(config) else { return }
        let url = URL(fileURLWithPath: defaultConfigPath())
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url)
        // Signal daemon (handles both mousefix and MouseFix process names)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        task.arguments = ["-HUP", "-i", "mousefix"]
        try? task.run()
    }
}

private let triggers = ["click", "double_click", "hold", "hold_scroll_up", "hold_scroll_down", "drag_up", "drag_down", "drag_left", "drag_right", "drag"]

private var actionNames: [String] {
    systemActions.keys.sorted()
}
