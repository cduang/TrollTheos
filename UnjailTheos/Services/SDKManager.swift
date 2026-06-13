import Foundation
import UniformTypeIdentifiers

/// SDK 统一管理：git 拉取、手动导入、列表扫描
@MainActor
final class SDKManager: ObservableObject {
    @Published var installedSDKs: [InstalledSDK] = []
    @Published var statusMessage: String?
    @Published var isProcessing = false
    @Published var downloadProgress = DownloadProgress()

    private let gitFetcher = SDKGitFetcher()
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

    /// 安装 SDK：内置包优先，其余走 git sparse-checkout
    func downloadAndExtract(source: SDKSource) async {
        isProcessing = true
        statusMessage = source.isBundled
            ? "正在安装 \(source.name)..."
            : "正在拉取 \(source.name)..."
        downloadProgress = DownloadProgress(phase: "准备中...")
        defer {
            isProcessing = false
            downloadProgress = DownloadProgress()
        }

        do {
            if source.isBundled {
                try await installBundledArchive(source: source)
            } else {
                if NetworkConfig.isProxyEnabled {
                    statusMessage = "正在拉取 \(source.name)（gh-proxy 加速）..."
                }

                try await gitFetcher.fetchSDK(folderName: source.sdkFolderName) { [weak self] phase in
                    Task { @MainActor in
                        self?.downloadProgress.phase = phase
                        self?.statusMessage = "正在拉取 \(source.name)... \(phase)"
                    }
                }
            }

            refreshInstalledSDKs()
            statusMessage = "\(source.name) 安装完成"
        } catch {
            statusMessage = "失败: \(error.localizedDescription)"
        }
    }

    /// 从 App Bundle（或本仓库 raw 回退）安装内置 .tar.xz SDK
    private func installBundledArchive(source: SDKSource) async throws {
        guard let baseName = source.bundledArchiveBaseName,
              let fileName = source.bundledArchiveFileName else {
            throw BundledSDKError.missingArchiveName
        }

        try TheosPaths.ensureDirectoryStructure()

        downloadProgress.phase = "读取内置 SDK 包..."
        statusMessage = "正在安装 \(source.name)..."

        let archiveURL: URL
        if let bundled = Bundle.main.url(forResource: baseName, withExtension: "tar.xz") {
            archiveURL = bundled
        } else {
            downloadProgress.phase = "从 GitHub 下载 SDK 包..."
            statusMessage = "内置包缺失，正在下载 \(source.name)..."
            archiveURL = try await downloadRemoteBundledArchive(fileName: fileName)
        }

        let destArchive = TheosPaths.cacheDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destArchive.path) {
            try FileManager.default.removeItem(at: destArchive)
        }
        try FileManager.default.copyItem(at: archiveURL, to: destArchive)

        downloadProgress.phase = "解压中..."
        statusMessage = "正在解压 \(source.name)..."
        try await extractor.extract(archiveURL: destArchive, destination: TheosPaths.sdksDirectory)
        try? FileManager.default.removeItem(at: destArchive)
    }

    /// 从 TrollTheos 仓库 raw 下载内置 SDK 包（Bundle 缺失时回退）
    private func downloadRemoteBundledArchive(fileName: String) async throws -> URL {
        let urlString = SDKSource.repoBundledSDKBase + fileName
        guard let remoteURL = URL(string: NetworkConfig.proxiedURLString(urlString)) else {
            throw BundledSDKError.invalidDownloadURL
        }

        let dest = TheosPaths.cacheDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }

        let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw BundledSDKError.downloadFailed
        }

        try FileManager.default.moveItem(at: tempURL, to: dest)
        return dest
    }

    enum BundledSDKError: LocalizedError {
        case missingArchiveName
        case invalidDownloadURL
        case downloadFailed

        var errorDescription: String? {
            switch self {
            case .missingArchiveName:
                return "未配置内置 SDK 包名"
            case .invalidDownloadURL:
                return "SDK 下载地址无效"
            case .downloadFailed:
                return "从 GitHub 下载 SDK 包失败"
            }
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
