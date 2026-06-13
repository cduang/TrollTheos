import Foundation
import UniformTypeIdentifiers

/// SDK 统一管理：下载、手动导入、列表扫描
@MainActor
final class SDKManager: ObservableObject {
    @Published var installedSDKs: [InstalledSDK] = []
    @Published var statusMessage: String?
    @Published var isProcessing = false

    let downloader = SDKDownloader()
    private let extractor = ArchiveExtractor()

    init() {
        refreshInstalledSDKs()
    }

    func refreshInstalledSDKs() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: TheosPaths.sdksDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            installedSDKs = []
            return
        }

        installedSDKs = contents
            .filter { $0.hasDirectoryPath || $0.pathExtension == "sdk" }
            .map { url in
                let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                return InstalledSDK(
                    id: url.lastPathComponent,
                    name: url.deletingPathExtension().lastPathComponent,
                    path: url,
                    installedAt: attrs?.contentModificationDate ?? Date()
                )
            }
            .sorted { $0.name < $1.name }
    }

    /// 下载并自动解压 SDK
    func downloadAndExtract(source: SDKSource) async {
        isProcessing = true
        statusMessage = "正在下载 \(source.name)..."
        defer { isProcessing = false }

        do {
            let archiveURL = try await downloader.download(source: source)
            statusMessage = "正在解压 \(source.name)..."
            try await extractor.extract(archiveURL: archiveURL, destination: TheosPaths.sdksDirectory)
            refreshInstalledSDKs()
            statusMessage = "\(source.name) 安装完成"
        } catch {
            statusMessage = "失败: \(error.localizedDescription)"
        }
    }

    /// 从 fileImporter 导入本地压缩包
    func importLocalArchive(from url: URL) async {
        isProcessing = true
        statusMessage = "正在导入 \(url.lastPathComponent)..."
        defer { isProcessing = false }

        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { url.stopAccessingSecurityScopedResource() }
        }

        do {
            try TheosPaths.ensureDirectoryStructure()
            let destArchive = TheosPaths.sdksDirectory.appendingPathComponent(url.lastPathComponent)

            if FileManager.default.fileExists(atPath: destArchive.path) {
                try FileManager.default.removeItem(at: destArchive)
            }
            try FileManager.default.copyItem(at: url, to: destArchive)

            statusMessage = "正在解压..."
            try await extractor.extract(archiveURL: destArchive, destination: TheosPaths.sdksDirectory)
            refreshInstalledSDKs()
            statusMessage = "导入完成"
        } catch {
            statusMessage = "导入失败: \(error.localizedDescription)"
        }
    }

    func deleteSDK(_ sdk: InstalledSDK) {
        try? FileManager.default.removeItem(at: sdk.path)
        refreshInstalledSDKs()
        statusMessage = "已删除 \(sdk.name)"
    }
}

/// 支持的 SDK 压缩包类型
extension UTType {
    static var sdkArchives: [UTType] {
        [.zip, .gzip, .data]
    }
}
