import CoreGraphics
import Foundation

public let systemActions: [String: (CGEventFlags, UInt16)] = [
    "mission_control":    ([.maskControl], 0x7E),
    "app_expose":         ([.maskControl], 0x7D),
    "show_desktop":       ([.maskCommand, .maskAlternate], 0x03),
    "launchpad":          ([], 0x76),
    "spotlight":          ([.maskCommand], 0x31),
    "back":               ([.maskCommand], 0x2B),
    "forward":            ([.maskCommand], 0x2F),
    "zoom_in":            ([.maskCommand], 0x12),
    "zoom_out":           ([.maskCommand], 0x13),
    "smart_zoom":         ([.maskControl, .maskCommand], 0x08),
    "screenshot":         ([.maskCommand, .maskShift], 0x04),
    "fullscreen":         ([.maskControl, .maskCommand], 0x03),
    "minimize":           ([.maskCommand], 0x1D),
    "close_window":       ([.maskCommand], 0x0D),
]

private let modifierAppleScriptMap: [String: String] = [
    "command": "command down",
    "control": "control down",
    "option": "option down",
    "shift": "shift down",
]

func executeAction(_ action: ActionDef) {
    switch action {
    case .system(let name):
        log("action: \(name)")
        if let (_, keyCode) = systemActions[name] {
            sendSystemKey(keyCode: keyCode, actionName: name)
        } else {
            log("  unknown system action: \(name)")
        }
    case .keyCombo(let combo):
        log("action: key combo 0x\(String(combo.keyCode, radix: 16)) mods=\(combo.modifiers)")
        sendKeyCombo(keyCode: combo.keyCode, modifierNames: combo.modifiers)
    }
}

private let scriptQueue = DispatchQueue(label: "osascript")

private func sendSystemKey(keyCode: UInt16, actionName: String) {
    let modStrings: [String]
    switch actionName {
    case "mission_control":
        modStrings = ["control down"]
    case "app_expose":
        modStrings = ["control down"]
    case "show_desktop":
        modStrings = ["command down", "option down"]
    case "launchpad":
        modStrings = []
    case "screenshot":
        modStrings = ["command down", "shift down"]
    default:
        modStrings = ["command down"]
    }
    runScript(keyCode: keyCode, modifiers: modStrings)
}

private func sendKeyCombo(keyCode: UInt16, modifierNames: [String]) {
    let modStrings = modifierNames.compactMap { modifierAppleScriptMap[$0.lowercased()] }
    if modStrings.isEmpty {
        runScript(keyCode: keyCode, modifiers: [])
    } else {
        runScript(keyCode: keyCode, modifiers: modStrings)
    }
}

private func runScript(keyCode: UInt16, modifiers: [String]) {
    let modPart = modifiers.isEmpty ? "" : " using {" + modifiers.joined(separator: ", ") + "}"
    let script = "tell application \"System Events\" to key code \(keyCode)" + modPart
    log("  osascript: \(script)")
    scriptQueue.async {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        try? task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            log("  osascript failed (code \(task.terminationStatus))")
        } else {
            log("  osascript OK")
        }
    }
}
