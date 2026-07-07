import CoreGraphics
import Foundation

public final class EventTapManager {
    nonisolated(unsafe) public static let shared = EventTapManager()

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRunning = false

    let scrollSmoother = ScrollSmoother.shared
    let buttonMapper = ButtonMapper.shared
    let scrollDirectionController = ScrollDirectionController.shared

    private let eventMask: CGEventMask = {
        var mask: CGEventMask = 0
        mask |= (1 << CGEventType.scrollWheel.rawValue)
        mask |= (1 << CGEventType.otherMouseDown.rawValue)
        mask |= (1 << CGEventType.otherMouseUp.rawValue)
        mask |= (1 << CGEventType.otherMouseDragged.rawValue)
        return mask
    }()

    private let tapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
        let manager = Unmanaged<EventTapManager>.fromOpaque(userInfo!).takeUnretainedValue()
        return manager.handle(event: event, type: type, proxy: proxy)
    }

    public func start(with config: AppConfig) -> Bool {
        scrollSmoother.config = config.smoothScrolling
        scrollDirectionController.config = config.scrollDirection
        buttonMapper.load(mappings: config.mappings)

        let opaque = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: tapCallback,
            userInfo: opaque
        ) else {
            return false
        }

        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let rls = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        return true
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        if let rls = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), rls, .commonModes)
        }
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        tap = nil
        runLoopSource = nil
    }

    private func handle(event: CGEvent, type: CGEventType, proxy: CGEventTapProxy) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            log("tap disabled (\(type == .tapDisabledByTimeout ? "timeout" : "user input")) — re-enabling")
            if let tap = tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return nil
        }

        switch type {
        case .scrollWheel:
            let heldButtons = buttonMapper.heldButtons
            if !heldButtons.isEmpty {
                let dy = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
                for btn in heldButtons {
                    if buttonMapper.processHeldScroll(button: btn, scrollDeltaY: -dy) {
                        return nil
                    }
                }
            }

            if scrollSmoother.config.enabled {
                _ = scrollSmoother.process(event: event)
                return nil
            }

            if scrollDirectionController.config.flipVertical || scrollDirectionController.config.flipHorizontal {
                var dy = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
                var dx = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
                scrollDirectionController.process(deltaY: &dy, deltaX: &dx)
                event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: dy)
                event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: dx)
                event.setDoubleValueField(.scrollWheelEventDeltaAxis1, value: dy)
                event.setDoubleValueField(.scrollWheelEventDeltaAxis2, value: dx)
            }

            return Unmanaged.passUnretained(event)

        case .otherMouseDown, .otherMouseUp:
            let btn = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            let kind = type == .otherMouseDown ? "down" : "up"
            log("event: btn \(btn) \(kind)")
            let consumed = buttonMapper.processButton(event: event, type: type)
            if consumed { log("  consumed") }
            return consumed ? nil : Unmanaged.passUnretained(event)

        case .otherMouseDragged:
            let btn = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            _ = buttonMapper.processDrag(button: btn, location: event.location)
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }
}
