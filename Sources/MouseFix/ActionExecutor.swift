import CoreGraphics
import Foundation

let systemActions: [String: (CGEventFlags, UInt16)] = [
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

private let modifierMap: [String: CGEventFlags] = [
    "command": .maskCommand,
    "control": .maskControl,
    "option": .maskAlternate,
    "shift": .maskShift,
    "fn": .maskSecondaryFn,
]

func executeAction(_ action: ActionDef) {
    switch action {
    case .system(let name):
        if let (modifiers, keyCode) = systemActions[name] {
            postKeyCombo(modifiers: modifiers, keyCode: keyCode)
        }
    case .keyCombo(let combo):
        var flags = CGEventFlags()
        for mod in combo.modifiers {
            if let f = modifierMap[mod.lowercased()] {
                flags.insert(f)
            }
        }
        postKeyCombo(modifiers: flags, keyCode: combo.keyCode)
    }
}

private func postKeyCombo(modifiers: CGEventFlags, keyCode: UInt16) {
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else { return }
    down.flags = modifiers
    guard let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else { return }
    up.flags = modifiers
    down.post(tap: .cgAnnotatedSessionEventTap)
    up.post(tap: .cgAnnotatedSessionEventTap)
}
