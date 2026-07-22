import SwiftUI
import AppKit
import MouseFixCore

private let modifierOrder = ["control", "option", "shift", "command"]
private let modifierSymbols: [String: String] = [
    "control": "⌃", "option": "⌥", "shift": "⇧", "command": "⌘",
]

private let keyCodeNames: [UInt16: String] = [
    0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G",
    0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q",
    0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y", 0x11: "T",
    0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5",
    0x18: "=", 0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0",
    0x1E: "]", 0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
    0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";", 0x2A: "\\",
    0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M", 0x2F: ".", 0x32: "`",
    0x24: "\u{21A9}", 0x30: "\u{21E5}", 0x31: "Space", 0x33: "\u{232B}", 0x35: "\u{238B}",
    0x4C: "\u{2324}",
    0x72: "Help", 0x73: "Home", 0x74: "Pg Up", 0x75: "\u{2326}",
    0x77: "End", 0x79: "Pg Dn",
    0x7B: "\u{2190}", 0x7C: "\u{2192}", 0x7D: "\u{2193}", 0x7E: "\u{2191}",
    0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5",
    0x61: "F6", 0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10",
    0x67: "F11", 0x6F: "F12", 0x69: "F13", 0x6B: "F14", 0x71: "F15",
    0x6A: "F16", 0x40: "F17", 0x4F: "F18", 0x50: "F19", 0x5A: "F20",
]

func keySymbol(for keyCode: UInt16) -> String {
    keyCodeNames[keyCode] ?? "Key 0x\(String(keyCode, radix: 16))"
}

func displayString(for combo: KeyCombo) -> String {
    let mods = modifierOrder.filter { combo.modifiers.contains($0) }.compactMap { modifierSymbols[$0] }.joined()
    return mods + keySymbol(for: combo.keyCode)
}

private func modifierStrings(from flags: NSEvent.ModifierFlags) -> [String] {
    var result: [String] = []
    if flags.contains(.control) { result.append("control") }
    if flags.contains(.option) { result.append("option") }
    if flags.contains(.shift) { result.append("shift") }
    if flags.contains(.command) { result.append("command") }
    return result
}

final class KeyCaptureNSView: NSView {
    var onCapture: ((UInt16, NSEvent.ModifierFlags) -> Void)?
    var displayText: String = "" {
        didSet { needsDisplay = true }
    }
    private var isRecording = false {
        didSet { needsDisplay = true }
    }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 120, height: 22) }

    override func becomeFirstResponder() -> Bool {
        isRecording = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return false }
        handle(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        handle(event)
    }

    private func handle(_ event: NSEvent) {
        defer { window?.makeFirstResponder(nil) }
        guard event.keyCode != 0x35 else { return } // Escape cancels
        onCapture?(event.keyCode, event.modifierFlags)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = 1
        path.stroke()

        let text = isRecording ? "Press keys… (Esc cancels)" : displayText
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor,
        ]
        let size = text.size(withAttributes: attrs)
        let rect = NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
        text.draw(in: rect, withAttributes: attrs)
    }
}

struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var combo: KeyCombo

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onCapture = { keyCode, flags in
            combo = KeyCombo(keyCode: keyCode, modifiers: modifierStrings(from: flags))
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.displayText = displayString(for: combo)
    }
}
