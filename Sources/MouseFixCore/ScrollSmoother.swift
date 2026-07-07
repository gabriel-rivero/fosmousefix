import CoreGraphics
import Foundation

final class ScrollSmoother {
    nonisolated(unsafe) static let shared = ScrollSmoother()

    var config: SmoothScrollingConfig = .init()
    var scrollDirectionController: ScrollDirectionController = .shared

    private var pendingX: Double = 0
    private var pendingY: Double = 0
    private var momentumX: Double = 0
    private var momentumY: Double = 0
    private var lastEventTime: CFAbsoluteTime = 0
    private var isAnimating = false
    private var timer: CFRunLoopTimer?
    private var frameInterval: Double = 1.0 / 60.0

    private var lastDeltaY: Double = 0
    private var lastDeltaX: Double = 0
    private var scrollCount: Int = 0
    private let momentumThreshold: Int = 2

    func process(event: CGEvent) -> Bool {
        guard config.enabled else { return false }

        var deltaY = -event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        var deltaX = -event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)

        scrollDirectionController.process(deltaY: &deltaY, deltaX: &deltaX)

        guard abs(deltaY) > 0 || abs(deltaX) > 0 else { return false }

        let now = CFAbsoluteTimeGetCurrent()
        let dt = min(now - lastEventTime, 0.5)
        lastEventTime = now

        if dt < 0.1 {
            scrollCount += 1
        } else {
            scrollCount = 0
            momentumX = 0
            momentumY = 0
        }

        lastDeltaY = deltaY
        lastDeltaX = deltaX

        pendingX += deltaX
        pendingY += deltaY

        if !isAnimating { startTimer() }

        return true
    }

    private func startTimer() {
        isAnimating = true
        let timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent(), frameInterval, 0, 0) { [weak self] _ in
            self?.tick()
        }
        self.timer = timer
        if let timer = timer {
            CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .commonModes)
        }
    }

    private func stopTimer() {
        if let timer = timer {
            CFRunLoopRemoveTimer(CFRunLoopGetCurrent(), timer, .commonModes)
        }
        timer = nil
        isAnimating = false
    }

    private func tick() {
        let factor = config.intensity * 0.25 + 0.05
        var dispatchX = pendingX * factor
        var dispatchY = pendingY * factor

        pendingX -= dispatchX
        pendingY -= dispatchY

        if scrollCount >= momentumThreshold && abs(lastDeltaY) > 0 {
            let momentumTarget = lastDeltaY * 0.15 * config.intensity
            momentumY += (momentumTarget - momentumY) * 0.3
        }
        if scrollCount >= momentumThreshold && abs(lastDeltaX) > 0 {
            let momentumTarget = lastDeltaX * 0.15 * config.intensity
            momentumX += (momentumTarget - momentumX) * 0.3
        }

        dispatchX += momentumX
        dispatchY += momentumY

        momentumX *= 0.88
        momentumY *= 0.88

        let stopThreshold = 0.3
        let hasMomentum = abs(momentumX) > stopThreshold || abs(momentumY) > stopThreshold

        if abs(dispatchX) < stopThreshold && abs(dispatchY) < stopThreshold &&
           abs(pendingX) < stopThreshold && abs(pendingY) < stopThreshold &&
           !hasMomentum {
            pendingX = 0; pendingY = 0
            momentumX = 0; momentumY = 0
            scrollCount = 0
            stopTimer()
            return
        }

        postScroll(deltaX: dispatchX, deltaY: dispatchY)
    }

    private func postScroll(deltaX: Double, deltaY: Double) {
        let ix = Int32(max(-120, min(120, deltaX)))
        let iy = Int32(max(-120, min(120, deltaY)))
        guard ix != 0 || iy != 0 else { return }
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: iy, wheel2: ix, wheel3: 0) else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.post(tap: .cgAnnotatedSessionEventTap)
    }
}
