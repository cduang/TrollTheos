import Foundation

/// Theos 项目构建执行器
@MainActor
final class BuildExecutor: ObservableObject {
    @Published var state: BuildState = .idle
    @Published var logs: [BuildLogEntry] = []

    private let rootHelper = RootHelperClient()
    private var buildTask: Task<Void, Never>?

    func build(projectPath: URL, theosPath: URL) {
        guard !state.isRunning else { return }

        buildTask?.cancel()
        logs.removeAll()
        state = .running
        appendSystemLog("开始构建: \(projectPath.lastPathComponent)")

        // 逐行实时回调 — 绑定 RootHelperClient.onLine
        rootHelper.onLine = { [weak self] line, stream in
            Task { @MainActor in
                self?.appendLine(line, stream: stream)
            }
        }

        buildTask = Task {
            do {
                let projectQ = PathSafety.shellQuote(projectPath.path)
                let theosQ = PathSafety.shellQuote(theosPath.path)

                // 使用 set -o pipefail 与合并 stderr，确保 make 输出实时到达 Pipe
                let command = """
                set -o pipefail; \
                export THEOS=\(theosQ); \
                export PATH="$THEOS/bin:/usr/local/bin:/usr/bin:/bin:$PATH"; \
                export LANG="${LANG:-C.UTF-8}"; \
                cd \(projectQ) && \
                make clean 2>/dev/null || true; \
                make package VERBOSE=1 2>&1
                """

                let result = try await rootHelper.execute(
                    command: command,
                    workingDirectory: projectPath.path,
                    environment: ["THEOS": theosPath.path]
                )

                if Task.isCancelled {
                    state = .idle
                    appendSystemLog("构建已取消")
                    return
                }

                if result.exitCode == 0 {
                    state = .succeeded(exitCode: result.exitCode)
                    appendSystemLog("构建成功 (exit: \(result.exitCode))")
                } else {
                    let msg = result.stderr.isEmpty ? result.stdout : result.stderr
                    state = .failed(exitCode: result.exitCode, message: msg)
                    appendSystemLog("构建失败 (exit: \(result.exitCode))")
                }
            } catch {
                state = .failed(exitCode: -1, message: error.localizedDescription)
                appendSystemLog("错误: \(error.localizedDescription)")
            }
        }
    }

    func cancel() {
        buildTask?.cancel()
        state = .idle
        appendSystemLog("构建已取消")
    }

    func clearLogs() {
        logs.removeAll()
    }

    private func appendLine(_ line: String, stream: BuildLogEntry.Stream) {
        guard !line.isEmpty else { return }
        logs.append(BuildLogEntry(timestamp: Date(), text: line, stream: stream))
    }

    private func appendSystemLog(_ text: String) {
        appendLine(text, stream: .system)
    }
}
