import CoreGraphics
import Foundation

final class ButtonMapper {
    nonisolated(unsafe) static let shared = ButtonMapper()

    private var mappings: [Int: [String: ActionDef]] = [:]
    private(set) var heldButtons: Set<Int> = []
    private var buttonDownTime: [Int: CFAbsoluteTime] = [:]
    private var buttonDownPos: [Int: CGPoint] = [:]
    private var buttonTriggerFired: Set<Int> = []

    private let clickTimeThreshold: CFAbsoluteTime = 0.3
    private let clickDistanceThreshold: Double = 20.0

    func load(mappings newMappings: [Mapping]) {
        var grouped: [Int: [String: ActionDef]] = [:]
        for m in newMappings {
            if grouped[m.button] == nil { grouped[m.button] = [:] }
            grouped[m.button]?[m.trigger] = m.action
        }
        self.mappings = grouped
    }

    private func action(for button: Int, trigger: String) -> ActionDef? {
        mappings[button]?[trigger]
    }

    func processButton(event: CGEvent, type: CGEventType) -> Bool {
        if type == .flagsChanged { return false }

        let buttonNum = event.getIntegerValueField(.mouseEventButtonNumber)
        guard buttonNum >= 2 else { return false }

        let btn = Int(buttonNum)

        if type == .otherMouseDown {
            log("btn \(btn) down")
            heldButtons.insert(btn)
            buttonDownTime[btn] = CFAbsoluteTimeGetCurrent()
            buttonDownPos[btn] = event.location
            buttonTriggerFired.remove(btn)
            return false
        }

        if type == .otherMouseUp {
            let held = CFAbsoluteTimeGetCurrent() - (buttonDownTime[btn] ?? 0)
            let hasDrag = buttonTriggerFired.contains(btn)
            log("btn \(btn) up  held=\(String(format: "%.2f", held))s")

            defer {
                heldButtons.remove(btn)
                buttonDownTime.removeValue(forKey: btn)
                buttonDownPos.removeValue(forKey: btn)
                buttonTriggerFired.remove(btn)
            }

            if hasDrag {
                log("  already fired drag — swallowing")
                return true
            }

            if held < clickTimeThreshold, let action = action(for: btn, trigger: "click") {
                log("  → click action")
                executeAction(action)
                return true
            } else if let action = action(for: btn, trigger: "hold") {
                log("  → hold action")
                executeAction(action)
                return true
            }

            log("  no mapping for btn \(btn) trigger=click")
            return false
        }

        return false
    }

    func processDrag(button: Int, location: CGPoint) -> Bool {
        guard heldButtons.contains(button),
              let start = buttonDownPos[button],
              !buttonTriggerFired.contains(button)
        else { return false }

        let dx = location.x - start.x
        let dy = location.y - start.y
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > clickDistanceThreshold else { return false }

        let direction: String
        if abs(dx) > abs(dy) {
            direction = dx > 0 ? "drag_right" : "drag_left"
        } else {
            direction = dy > 0 ? "drag_down" : "drag_up"
        }

        if let action = action(for: button, trigger: direction)
            ?? action(for: button, trigger: "drag") {
            executeAction(action)
            buttonTriggerFired.insert(button)
            return true
        }
        return false
    }

    func processHeldScroll(button: Int, scrollDeltaY: Double) -> Bool {
        guard heldButtons.contains(button), scrollDeltaY != 0,
              !buttonTriggerFired.contains(button)
        else { return false }

        let trigger = scrollDeltaY > 0 ? "hold_scroll_up" : "hold_scroll_down"
        if let action = action(for: button, trigger: trigger) {
            executeAction(action)
            buttonTriggerFired.insert(button)
            return true
        }
        return false
    }
}
