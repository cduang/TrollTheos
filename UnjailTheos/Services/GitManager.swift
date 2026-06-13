import Foundation

/// GitHub 云端构建配置
struct GitHubBuildConfig: Codable {
    var repositoryURL: String = ""
    var branch: String = "main"
    var token: String = ""
    var authorName: String = "UnjailTheos"
    var authorEmail: String = "unjailtheos@local.dev"
    var workflowFileName: String = "build.yml"
}

/// Git 仓库解析结果
struct GitHubRepoIdentity: Equatable {
    let owner: String
    let repo: String

    var httpsURL: String { "https://github.com/\(owner)/\(repo).git" }
}

/// 迷你 Git 封装 + GitHub REST API 触发 Actions
@MainActor
final class GitManager: ObservableObject {
    @Published var config = GitHubBuildConfig()
    @Published var statusMessage: String?
    @Published var isWorking = false
    @Published var lastPushLog: String = ""
    @Published var lastReleaseURL: String?

    private let rootHelper = RootHelperClient()
    private let gitPath = "/usr/bin/git"

    // MARK: - Workflow 模板（与项目根 .github/workflows/build.yml 同步）

    /// 从 Bundle 读取或使用内嵌模板
    static var workflowYAML: String {
        if let url = Bundle.main.url(forResource: "build", withExtension: "yml"),
           let content = try? String(contentsOf: url, encoding: .utf8),
           !content.isEmpty {
            return content
        }
        return embeddedWorkflowYAML
    }

    /// 内嵌 fallback（与 .github/workflows/build.yml 保持一致）
    private static let embeddedWorkflowYAML = """
    name: Build Tweak
    on:
      push:
        branches: [main, master]
      workflow_dispatch:
    permissions:
      contents: write
    jobs:
      build:
        runs-on: macos-latest
        env:
          SDK_NAME: iPhoneOS15.6.sdk
          SDK_VERSION: "15.6"
          SDK_TARBALL_URL: https://raw.githubusercontent.com/cduang/TrollTheos/main/iPhoneOS15.6.sdk.tar.xz
        steps:
          - uses: actions/checkout@v4
          - run: |
              git clone --recursive --depth 1 https://github.com/theos/theos.git $HOME/theos
              mkdir -p $HOME/theos/sdks
              curl -fsSL -o /tmp/sdk.tar.xz "$SDK_TARBALL_URL"
              tar -xJf /tmp/sdk.tar.xz -C $HOME/theos/sdks
              rm -f /tmp/sdk.tar.xz
              export THEOS=$HOME/theos PATH="$HOME/theos/bin:$PATH"
              make package ARCHS=arm64 TARGET=iphone:clang:${SDK_VERSION}:${SDK_VERSION} || true
              make package ARCHS=arm64e TARGET=iphone:clang:${SDK_VERSION}:${SDK_VERSION} \
                THEOS_PACKAGE_SCHEME=rootless DEB_ARCH=iphoneos-arm64e || true
          - uses: actions/upload-artifact@v4
            with:
              name: tweak-packages
              path: dist/*.deb
    """

    // MARK: - 公开 API

    /// 生成 workflow 文件到 Tweak 项目目录
    func generateWorkflow(in projectPath: URL) throws {
        let workflowDir = projectPath
            .appendingPathComponent(".github/workflows", isDirectory: true)
        try FileManager.default.createDirectory(at: workflowDir, withIntermediateDirectories: true)
        let workflowFile = workflowDir.appendingPathComponent(config.workflowFileName)
        try Self.workflowYAML.write(to: workflowFile, atomically: true, encoding: .utf8)
    }

    /// 初始化本地 Git 仓库
    func setupRepo(at projectPath: URL) async throws {
        try await runGit(
            at: projectPath,
            command: buildSetupRepoCommand(projectPath: projectPath)
        )
    }

    /// 提交本地更改
    func commitChanges(at projectPath: URL, message: String) async throws {
        let msgQ = PathSafety.shellQuote(message)
        let cmd = """
        set -e; \
        \(gitQ) add -A && \
        \(gitQ) diff --cached --quiet && exit 0 || \
        \(gitQ) commit -m \(msgQ)
        """
        try await runGit(at: projectPath, command: cmd)
    }

    /// 推送到 GitHub（HTTPS + PAT 鉴权）
    func pushToGitHub(
        at projectPath: URL,
        repoUrl: String,
        token: String,
        branch: String? = nil
    ) async throws {
        let branchName = branch ?? config.branch
        let identity = try parseRepoIdentity(from: repoUrl)
        let authURL = embedToken(in: identity.httpsURL, token: token)

        let authQ = PathSafety.shellQuote(authURL)
        let branchQ = PathSafety.shellQuote(branchName)

        let cmd = """
        set -e; \
        \(gitQ) remote remove origin 2>/dev/null || true; \
        \(gitQ) remote add origin \(authQ); \
        \(gitQ) branch -M \(branchQ); \
        GIT_TERMINAL_PROMPT=0 \(gitQ) -c credential.helper= push -u origin \(branchQ) --force
        """

        try await runGit(at: projectPath, command: cmd)
    }

    /// 通过 GitHub REST API 触发 workflow_dispatch
    func triggerWorkflowDispatch(
        repo: String,
        token: String,
        workflowFile: String? = nil,
        branch: String? = nil,
        inputs: [String: String] = [:]
    ) async throws {
        let identity = try parseRepoIdentity(from: repo)
        let wf = workflowFile ?? config.workflowFileName
        let ref = branch ?? config.branch

        let apiURL = URL(string: "https://api.github.com/repos/\(identity.owner)/\(identity.repo)/actions/workflows/\(wf)/dispatches")!
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("UnjailTheos/1.0", forHTTPHeaderField: "User-Agent")

        var body: [String: Any] = ["ref": ref]
        if !inputs.isEmpty {
            body["inputs"] = inputs
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitError.apiFailed("无效响应")
        }

        // 204 No Content 表示成功
        guard (200...299).contains(http.statusCode) || http.statusCode == 204 else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw GitError.apiFailed(msg)
        }
    }

    /// 一键：生成 workflow → 初始化 → 提交 → 推送 → 触发 Actions
    func pushAndBuild(projectPath: URL) async {
        guard !config.repositoryURL.isEmpty, !config.token.isEmpty else {
            statusMessage = "请填写仓库 URL 和 Personal Access Token"
            return
        }

        isWorking = true
        statusMessage = "准备云端构建..."
        lastReleaseURL = nil
        defer { isWorking = false }

        do {
            appendLog("生成 GitHub Actions workflow...")
            try generateWorkflow(in: projectPath)

            appendLog("初始化本地 Git 仓库...")
            try await setupRepo(at: projectPath)

            appendLog("提交本地更改...")
            try await commitChanges(
                at: projectPath,
                message: "UnjailTheos: cloud build \(ISO8601DateFormatter().string(from: Date()))"
            )

            appendLog("推送到 GitHub...")
            try await pushToGitHub(
                at: projectPath,
                repoUrl: config.repositoryURL,
                token: config.token,
                branch: config.branch
            )

            appendLog("触发 workflow_dispatch...")
            try await triggerWorkflowDispatch(
                repo: config.repositoryURL,
                token: config.token,
                branch: config.branch
            )

            let identity = try parseRepoIdentity(from: config.repositoryURL)
            lastReleaseURL = "https://github.com/\(identity.owner)/\(identity.repo)/actions"
            statusMessage = "推送成功，云端构建已触发"
            appendLog("Actions 页面: \(lastReleaseURL!)")
        } catch {
            statusMessage = "失败: \(error.localizedDescription)"
            appendLog("错误: \(error.localizedDescription)")
        }
    }

    // MARK: - 内部 Git 命令

    private var gitQ: String { PathSafety.shellQuote(gitPath) }

    private func buildSetupRepoCommand(projectPath: URL) -> String {
        let nameQ = PathSafety.shellQuote(config.authorName)
        let emailQ = PathSafety.shellQuote(config.authorEmail)
        return """
        set -e; \
        \(gitQ) init && \
        \(gitQ) config user.name \(nameQ) && \
        \(gitQ) config user.email \(emailQ) && \
        \(gitQ) config credential.helper "" && \
        \(gitQ) config http.extraHeader "x-unjailtheos: 1"
        """
    }

    private func runGit(at projectPath: URL, command: String) async throws {
        var lines: [String] = []
        rootHelper.onLine = { line, stream in
            let prefix = stream == .stderr ? "[git stderr] " : ""
            lines.append(prefix + line)
        }

        let result = try await rootHelper.execute(
            command: command,
            workingDirectory: projectPath.path
        )

        let log = lines.joined(separator: "\n")
        lastPushLog += log + "\n"
        if !result.stdout.isEmpty { lastPushLog += result.stdout }
        if !result.stderr.isEmpty { lastPushLog += result.stderr }

        guard result.exitCode == 0 else {
            throw GitError.commandFailed(exitCode: result.exitCode, log: log.isEmpty ? result.stderr : log)
        }
    }

    private func appendLog(_ text: String) {
        lastPushLog += text + "\n"
    }

    // MARK: - URL / Token 处理

    /// 拼接 PAT 鉴权 URL: https://<token>@github.com/owner/repo.git
    func embedToken(in repoURL: String, token: String) -> String {
        let trimmed = repoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.hasSuffix(".git") ? trimmed : trimmed + ".git"

        guard var components = URLComponents(string: normalized) else {
            return normalized
        }

        // 清除已有凭证
        components.user = nil
        components.password = nil

        // PAT 作为 user 嵌入: https://<token>@github.com/owner/repo.git
        components.user = token
        components.password = nil

        return components.string ?? normalized
    }

    /// 从 URL 解析 owner/repo
    func parseRepoIdentity(from repoString: String) throws -> GitHubRepoIdentity {
        var cleaned = repoString.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: ".git", with: "")

        // 去除 token 部分 https://token@github.com/...
        if let url = URLComponents(string: cleaned), let host = url.host {
            if host.contains("github.com") {
                let path = url.path.split(separator: "/").map(String.init)
                if path.count >= 2 {
                    return GitHubRepoIdentity(owner: path[0], repo: path[1])
                }
            }
        }

        // 手动解析
        if cleaned.contains("github.com") {
            let parts = cleaned.components(separatedBy: "github.com/")
            if parts.count == 2 {
                let segments = parts[1].split(separator: "/").map(String.init)
                if segments.count >= 2 {
                    return GitHubRepoIdentity(owner: segments[0], repo: segments[1])
                }
            }
        }

        // owner/repo 简写
        let segments = cleaned.split(separator: "/").map(String.init)
        if segments.count == 2 {
            return GitHubRepoIdentity(owner: segments[0], repo: segments[1])
        }

        throw GitError.invalidRepoURL(repoString)
    }

    enum GitError: LocalizedError {
        case invalidRepoURL(String)
        case commandFailed(exitCode: Int32, log: String)
        case apiFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidRepoURL(let url):
                return "无法解析仓库 URL: \(url)"
            case .commandFailed(let code, let log):
                return "Git 命令失败 (exit \(code)): \(log)"
            case .apiFailed(let msg):
                return "GitHub API 失败: \(msg)"
            }
        }
    }
}
