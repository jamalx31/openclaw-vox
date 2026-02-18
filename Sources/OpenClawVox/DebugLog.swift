import Foundation

private let _logDateFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    return f
}()

func ocvLog(_ tag: String = "App", _ message: String) {
    let ts = _logDateFormatter.string(from: Date())
    print("[OpenClawVox/\(tag)][\(ts)] \(message)")
}
