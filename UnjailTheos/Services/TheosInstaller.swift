import Foundation

/// Theos 工具链自动安装器
///
/// 首次启动检测到本地无 Theos 时：
/// 1. 优先 git clone --recursive（完整 submodule）
/// 2. 回退下载 GitHub master.zip 并解压，再尝试 submodule init
@MainActor
final class TheosInstaller: ObservableObject {
    @Published var state: InstallState = .idle
    @Published var progressMessage: String = ""
    @Published var downloadProgress = DownloadProgress()

    enum InstallState: Equatable {
        case idle
        case checking
        case installing
        case installed
        case failed(String)
    }

    private let rootHelper = RootHelperClient()
    private let extractor = ArchiveExtractor()

    /// GitHub 官方 Theos 源（原始 URL，使用时经 NetworkConfig 代理）
    static let theosGitURLOriginal = "https://github.com/theos/theos.git"
    static let theosZipURLOriginal = "https://github.com/theos/theos/archive/refs/heads/master.zip"

    /// 经 gh-proxy 加速后的 Git URL
    static var theosGitURL: String {
        NetworkConfig.proxiedURLString(theosGitURLOriginal)
    }

    /// 经 gh-proxy 加速后的 Zip 下载 URL
    static var theosZipURL: URL {
        let original = URL(string: theosZipURLOriginal)!
        return NetworkConfig.proxiedURL(original)
    }

    private let gitPath = "/usr/bin/git"

    /// 检测 Theos 是否已安装
    static func isTheosInstalled() -> Bool {
        TheosPaths.isTheosInstalled()
    }

    /// 应用启动时调用：若未安装则自动安装
    func ensureTheosInstalledIfNeeded() async {
        guard !Self.isTheosInstalled() else {
            state = .installed
            progressMessage = "Theos 已就绪"
            return
        }

        state = .checking
        progressMessage = "检测到本地无 Theos，开始自动安装..."
        await installTheos()
    }

    /// 手动触发安装/重装
    func installTheos(force: Bool = false) async {
        if force {
            // 保留 sdks/ 子目录，清除其余
            await preserveSDKsAndCleanTheosRoot()
        } else if Self.isTheosInstalled() {
            state = .installed
            progressMessage = "Theos 已安装"
            return
        }

        state = .installing
        do {
            try TheosPaths.ensureDirectoryStructure()

            let gitAvailable = FileManager.default.isExecutableFile(atPath: gitPath)
            if gitAvailable {
                progressMessage = "正在 git clone Theos（含 submodule）..."
                try await installViaGitClone()
            } else {
                progressMessage = "git 不可用，正在下载 master.zip..."
                try await installViaZipDownload()
            }

            if Self.isTheosInstalled() {
                state = .installed
                progressMessage = "Theos 安装完成: \(TheosPaths.theosRoot.path)"
            } else {
                throw InstallError.verificationFailed
            }
        } catch {
            state = .failed(error.localizedDescription)
            progressMessage = "安装失败: \(error.localizedDescription)"
        }
    }

    // MARK: - Git Clone 安装

    private func installViaGitClone() async throws {
        let theosRoot = TheosPaths.theosRoot
        let cacheDir = TheosPaths.cacheDirectory
        let cloneTarget = cacheDir.appendingPathComponent("theos-clone", isDirectory: true)
        let sdksBackup = cacheDir.appendingPathComponent("sdks-backup", isDirectory: true)

        // 备份已有 sdks/
        try backupSDKs(to: sdksBackup)

        // 清理旧 clone 目录
        if FileManager.default.fileExists(atPath: cloneTarget.path) {
            try FileManager.default.removeItem(at: cloneTarget)
        }
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let cloneCmd = """
        set -e; \
        \(PathSafety.shellQuote(gitPath)) clone --recursive --depth 1 \
        -b master \(PathSafety.shellQuote(Self.theosGitURL)) \
        \(PathSafety.shellQuote(cloneTarget.path))
        """

        var cloneLog: [String] = []
        rootHelper.onLine = { line, _ in cloneLog.append(line) }

        let cloneResult = try await rootHelper.execute(command: cloneCmd)
        guard cloneResult.exitCode == 0 else {
            throw InstallError.commandFailed(
                "git clone",
                cloneResult.stderr.isEmpty ? cloneLog.joined(separator: "\n") : cloneResult.stderr
            )
        }

        // 将 clone 内容合并到 theosRoot（保留 sdks/）
        try mergeTheosClone(from: cloneTarget, to: theosRoot)
        try restoreSDKs(from: sdksBackup)

        try? FileManager.default.removeItem(at: cloneTarget)
        try? FileManager.default.removeItem(at: sdksBackup)
    }

    // MARK: - Zip 下载安装

    private func installViaZipDownload() async throws {
        let cacheDir = TheosPaths.cacheDirectory
        let zipDest = cacheDir.appendingPathComponent("theos-master.zip")
        let extractDir = cacheDir.appendingPathComponent("theos-extract", isDirectory: true)
        let sdksBackup = cacheDir.appendingPathComponent("sdks-backup", isDirectory: true)

        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try backupSDKs(to: sdksBackup)

        progressMessage = "正在下载 Theos master.zip..."
        if NetworkConfig.isProxyEnabled {
            progressMessage += "（加速模式: gh-proxy）"
        }
        try await downloadTheosZip(to: zipDest)

        if FileManager.default.fileExists(atPath: extractDir.path) {
            try FileManager.default.removeItem(at: extractDir)
        }
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        progressMessage = "正在解压 Theos..."
        try await extractor.extract(archiveURL: zipDest, destination: extractDir)

        // GitHub zip 解压后为 theos-master/
        let extractedTheos = extractDir.appendingPathComponent("theos-master", isDirectory: true)
        guard FileManager.default.fileExists(atPath: extractedTheos.path) else {
            throw InstallError.extractLayoutUnexpected
        }

        try mergeTheosClone(from: extractedTheos, to: TheosPaths.theosRoot)
        try restoreSDKs(from: sdksBackup)

        // zip 不含 submodule，尝试 git submodule init
        if FileManager.default.isExecutableFile(atPath: gitPath) {
            progressMessage = "正在初始化 submodule..."
            await initSubmodules()
        }

        try? FileManager.default.removeItem(at: zipDest)
        try? FileManager.default.removeItem(at: extractDir)
        try? FileManager.default.removeItem(at: sdksBackup)
    }

    private func downloadTheosZip(to destination: URL) async throws {
        let downloadURL = Self.theosZipURL

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let task = URLSession.shared.downloadTask(with: downloadURL) { tempURL, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let tempURL else {
                    continuation.resume(throwing: InstallError.downloadFailed("无临时文件"))
                    return
                }
                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: destination)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            // 进度观察
            let observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                Task { @MainActor in
                    self?.downloadProgress = DownloadProgress(
                        bytesReceived: progress.completedUnitCount,
                        totalBytes: progress.totalUnitCount
                    )
                }
            }
            _ = observation
            task.resume()
        }
    }

    private func initSubmodules() async {
        let theosQ = PathSafety.shellQuote(TheosPaths.theosRoot.path)
        let gitQ = PathSafety.shellQuote(gitPath)
        let cmd = """
        set -e; \
        cd \(theosQ) && \
        if [ ! -d .git ]; then \
          \(gitQ) init && \
          \(gitQ) remote add origin \(PathSafety.shellQuote(NetworkConfig.proxiedURLString(Self.theosGitURLOriginal))) && \
          \(gitQ) fetch --depth 1 origin master && \
          \(gitQ) checkout FETCH_HEAD; \
        fi && \
        \(gitQ) submodule update --init --recursive
        """
        _ = try? await rootHelper.execute(command: cmd)
    }

    // MARK: - 文件操作

    private func backupSDKs(to backupURL: URL) throws {
        let sdks = TheosPaths.sdksDirectory
        if FileManager.default.fileExists(atPath: backupURL.path) {
            try FileManager.default.removeItem(at: backupURL)
        }
        if FileManager.default.fileExists(atPath: sdks.path) {
            try FileManager.default.copyItem(at: sdks, to: backupURL)
        }
    }

    private func restoreSDKs(from backupURL: URL) throws {
        let sdks = TheosPaths.sdksDirectory
        guard FileManager.default.fileExists(atPath: backupURL.path) else { return }
        if FileManager.default.fileExists(atPath: sdks.path) {
            try FileManager.default.removeItem(at: sdks)
        }
        try FileManager.default.copyItem(at: backupURL, to: sdks)
    }

    private func mergeTheosClone(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        let items = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        for item in items {
            let name = item.lastPathComponent
            // 不覆盖已有 sdks 目录
            if name == "sdks" { continue }

            let destItem = destination.appendingPathComponent(name)
            if fm.fileExists(atPath: destItem.path) {
                try fm.removeItem(at: destItem)
            }
            try fm.copyItem(at: item, to: destItem)
        }
    }

    private func preserveSDKsAndCleanTheosRoot() async {
        let theosRoot = TheosPaths.theosRoot
        let cacheDir = TheosPaths.cacheDirectory
        let sdksBackup = cacheDir.appendingPathComponent("sdks-backup-reinstall", isDirectory: true)
        try? backupSDKs(to: sdksBackup)

        if FileManager.default.fileExists(atPath: theosRoot.path) {
            let items = (try? FileManager.default.contentsOfDirectory(at: theosRoot, includingPropertiesForKeys: nil)) ?? []
            for item in items where item.lastPathComponent != "sdks" {
                try? FileManager.default.removeItem(at: item)
            }
        }
    }

    enum InstallError: LocalizedError {
        case downloadFailed(String)
        case commandFailed(String, String)
        case extractLayoutUnexpected
        case verificationFailed

        var errorDescription: String? {
            switch self {
            case .downloadFailed(let msg): return "下载失败: \(msg)"
            case .commandFailed(let cmd, let log): return "\(cmd) 失败: \(log)"
            case .extractLayoutUnexpected: return "解压目录结构不符合预期（缺少 theos-master/）"
            case .verificationFailed: return "安装完成但校验失败，请检查 Makefile 与 bin/nic.pl"
            }
        }
    }
}
