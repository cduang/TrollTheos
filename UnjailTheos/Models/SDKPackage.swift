import Foundation

/// 预定义的 SDK 源
struct SDKSource: Identifiable, Hashable {
    let id: String
    let name: String
    /// 解压后的 SDK 目录名
    let sdkFolderName: String
    /// 内置 .tar.xz 基础名（不含扩展名）；有值时优先从 App Bundle 安装
    let bundledArchiveBaseName: String?

    var isBundled: Bool { bundledArchiveBaseName != nil }

    var bundledArchiveFileName: String? {
        bundledArchiveBaseName.map { "\($0).tar.xz" }
    }

    static let predefined: [SDKSource] = [
        SDKSource(
            id: "iphoneos15.6",
            name: "iPhoneOS 15.6",
            sdkFolderName: "iPhoneOS15.6.sdk",
            bundledArchiveBaseName: "iPhoneOS15.6.sdk"
        ),
        SDKSource(
            id: "iphoneos16.5",
            name: "iPhoneOS 16.5",
            sdkFolderName: "iPhoneOS16.5.sdk",
            bundledArchiveBaseName: nil
        ),
        SDKSource(
            id: "iphoneos14.5",
            name: "iPhoneOS 14.5",
            sdkFolderName: "iPhoneOS14.5.sdk",
            bundledArchiveBaseName: nil
        )
    ]

    /// 本仓库托管的内置 SDK 下载地址（Bundle 缺失时的回退）
    static let repoBundledSDKBase = "https://raw.githubusercontent.com/cduang/TrollTheos/main/"
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
