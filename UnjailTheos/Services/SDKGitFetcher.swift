import Foundation

/// 通过 git sparse-checkout 从 theos/sdks 仓库拉取 SDK 目录
///
/// theos/sdks 已不再提供 .tar.xz 直链，SDK 以 Git 目录形式维护。
final class SDKGitFetcher {
    enum FetchError: LocalizedError {
        case gitUnavailable
        case fetchFailed(exitCode: Int32, log: String)
        case sdkNotFound(String)

        var errorDescription: String? {
            switch self {
            case .gitUnavailable:
                return "未找到 /usr/bin/git"
            case .fetchFailed(let code, let log):
                return "SDK 拉取失败 (exit \(code)): \(log)"
            case .sdkNotFound(let name):
                return "未找到 SDK 目录: \(name)"
            }
        }
    }

    private let rootHelper = RootHelperClient()
    private let gitPath = "/usr/bin/git"
    private let sdksRepoOriginal = "https://github.com/theos/sdks.git"

    /// 拉取指定 SDK 到 Theos sdks 目录
    func fetchSDK(folderName: String, onPhase: ((String) -> Void)? = nil) async throws {
        guard FileManager.default.isExecutableFile(atPath: gitPath) else {
            throw FetchError.gitUnavailable
        }

        try TheosPaths.ensureDirectoryStructure()

        let sdksRepo = NetworkConfig.proxiedURLString(sdksRepoOriginal)
        let cacheDir = TheosPaths.cacheDirectory.appendingPathComponent("sdk-\(folderName)", isDirectory: true)
        let destSDK = TheosPaths.sdksDirectory.appendingPathComponent(folderName, isDirectory: true)

        onPhase?("git sparse-checkout \(folderName)...")

        let cacheQ = PathSafety.shellQuote(cacheDir.path)
        let destQ = PathSafety.shellQuote(destSDK.path)
        let repoQ = PathSafety.shellQuote(sdksRepo)
        let gitQ = PathSafety.shellQuote(gitPath)
        let folderQ = PathSafety.shellQuote(folderName)

        let cmd = """
        set -e; \
        rm -rf \(cacheQ); \
        \(gitQ) clone --depth 1 --filter=blob:none --sparse \
          \(repoQ) \(cacheQ); \
        cd \(cacheQ); \
        \(gitQ) sparse-checkout set \(folderQ); \
        test -d \(folderQ) || { echo "SDK directory not found: \(folderName)"; exit 1; }; \
        rm -rf \(destQ); \
        cp -a \(folderQ) \(destQ)
        """

        var logLines: [String] = []
        rootHelper.onLine = { line, stream in
            let prefix = stream == .stderr ? "[stderr] " : ""
            logLines.append(prefix + line)
        }

        let result = try await rootHelper.execute(command: cmd)
        guard result.exitCode == 0 else {
            let log = logLines.joined(separator: "\n")
            throw FetchError.fetchFailed(
                exitCode: result.exitCode,
                log: log.isEmpty ? (result.stderr + result.stdout) : log
            )
        }

        guard FileManager.default.fileExists(atPath: destSDK.path) else {
            throw FetchError.sdkNotFound(folderName)
        }

        try? FileManager.default.removeItem(at: cacheDir)
        onPhase?("完成")
    }
}
