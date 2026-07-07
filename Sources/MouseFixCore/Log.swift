import Foundation

nonisolated(unsafe) public var verboseEnabled = false

func log(_ msg: String) {
    guard verboseEnabled else { return }
    FileHandle.standardError.write(Data("[mousefix] \(msg)\n".utf8))
}
