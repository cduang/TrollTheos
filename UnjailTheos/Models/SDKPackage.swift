import Foundation

/// 预定义的在线 SDK 源
struct SDKSource: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let filename: String

    static let predefined: [SDKSource] = [
        SDKSource(
            id: "iphoneos16.5",
            name: "iPhoneOS 16.5",
            url: URL(string: "https://github.com/theos/sdks/raw/master/iPhoneOS16.5.sdk.tar.xz")!,
            filename: "iPhoneOS16.5.sdk.tar.xz"
        ),
        SDKSource(
            id: "iphoneos15.6",
            name: "iPhoneOS 15.6",
            url: URL(string: "https://github.com/theos/sdks/raw/master/iPhoneOS15.6.sdk.tar.xz")!,
            filename: "iPhoneOS15.6.sdk.tar.xz"
        ),
        SDKSource(
            id: "iphoneos14.5",
            name: "iPhoneOS 14.5",
            url: URL(string: "https://github.com/theos/sdks/raw/master/iPhoneOS14.5.sdk.tar.xz")!,
            filename: "iPhoneOS14.5.sdk.tar.xz"
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

    var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesReceived) / Double(totalBytes)
    }

    var formattedProgress: String {
        let received = ByteCountFormatter.string(fromByteCount: bytesReceived, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        return "\(received) / \(total)"
    }
}
