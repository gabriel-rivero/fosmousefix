import CoreGraphics

final class ScrollDirectionController {
    nonisolated(unsafe) static let shared = ScrollDirectionController()

    var config: ScrollDirectionConfig = .init()

    func process(deltaY: inout Double, deltaX: inout Double) {
        if config.flipVertical { deltaY = -deltaY }
        if config.flipHorizontal { deltaX = -deltaX }
    }
}
