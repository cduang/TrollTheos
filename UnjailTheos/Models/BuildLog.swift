import Foundation

/// 构建日志条目
struct BuildLogEntry: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let text: String
    let stream: Stream

    enum Stream: String {
        case stdout
        case stderr
        case system

        var prefix: String {
            switch self {
            case .stdout: return ""
            case .stderr: return "[ERR] "
            case .system: return "[SYS] "
            }
        }
    }

    var displayText: String {
        stream.prefix + text
    }
}

/// 构建状态
enum BuildState: Equatable {
    case idle
    case running
    case succeeded(exitCode: Int32)
    case failed(exitCode: Int32, message: String)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}
