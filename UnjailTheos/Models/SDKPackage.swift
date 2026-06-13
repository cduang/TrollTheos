import Foundation

/// 预定义的在线 SDK 源
struct SDKSource: Identifiable, Hashable {
    let id: String
    let name: String
    /// theos/sdks 仓库中的 SDK 目录名
    let sdkFolderName: String

    static let predefined: [SDKSource] = [
        SDKSource(
            id: "iphoneos16.5",
            name: "iPhoneOS 16.5",
            sdkFolderName: "iPhoneOS16.5.sdk"
        ),
        SDKSource(
            id: "iphoneos15.6",
            name: "iPhoneOS 15.6",
            sdkFolderName: "iPhoneOS15.6.sdk"
        ),
        SDKSource(
            id: "iphoneos14.5",
            name: "iPhoneOS 14.5",
            sdkFolderName: "iPhoneOS14.5.sdk"
        )
    ]
}

/// 已安装的 SDK 信息
struct InstalledSDK: Identifiable, Hashable {
    let id: String
    let name: String
    let path: URL
    let installedAt: Date
}

/// SDK 下载进度
struct DownloadProgress {
    var bytesReceived: Int64 = 0
    var totalBytes: Int64 = 0
    var phase: String = ""

    var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesReceived) / Double(totalBytes)
    }

    var formattedProgress: String {
        if totalBytes > 0 {
            let received = ByteCountFormatter.string(fromByteCount: bytesReceived, countStyle: .file)
            let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
            return "\(received) / \(total)"
        }
        return phase.isEmpty ? "进行中..." : phase
    }
}
