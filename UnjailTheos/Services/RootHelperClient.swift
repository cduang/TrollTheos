import Foundation
import Darwin

/// Root Helper 执行结果
struct HelperResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

/// 逐行流缓冲：处理 Pipe 分片到达的不完整行
final class StreamLineBuffer {
    private var pending = ""

    /// 喂入新 chunk，返回已完成的行
    func feed(_ chunk: String) -> [String] {
        guard !chunk.isEmpty else { return [] }
        pending += chunk
        var lines: [String] = []
        while let range = pending.range(of: "\n") {
            let line = String(pending[pending.startIndex..<range.lowerBound])
            lines.append(line)
            pending.removeSubrange(pending.startIndex...range.lowerBound)
        }
        return lines
    }

    /// 刷新剩余未换行内容
    func flush() -> String? {
        guard !pending.isEmpty else { return nil }
        defer { pending = "" }
        return pending
    }
}

/// Root Helper 客户端
///
/// 通过 posix_spawn 启动 roothelper（或 /bin/sh 回退），
/// 使用 Pipe 重定向 stdout/stderr，read(2) 循环实时读取并逐行回调。
final class RootHelperClient: @unchecked Sendable {
    enum HelperError: LocalizedError {
        case binaryNotFound
        case spawnFailed(Int32)
        case pipeFailed
        case fcntlFailed

        var errorDescription: String? {
            switch self {
            case .binaryNotFound:
                return "未找到 Root Helper 二进制文件"
            case .spawnFailed(let code):
                return "posix_spawn 失败，错误码: \(code)"
            case .pipeFailed:
                return "管道创建失败"
            case .fcntlFailed:
                return "设置非阻塞 IO 失败"
            }
        }
    }

    /// 实时日志回调（已按行拆分）
    var onLine: ((String, BuildLogEntry.Stream) -> Void)?

    /// 原始 chunk 回调（兼容旧接口）
    var onOutput: ((String, BuildLogEntry.Stream) -> Void)? {
        didSet {
            if onOutput != nil && onLine == nil {
                // 自动桥接：chunk -> 行
            }
        }
    }

    private let readBufferSize = 4096
    private var helperPath: String { TheosPaths.rootHelperBinary.path }

    func execute(
        command: String,
        workingDirectory: String? = nil,
        environment: [String: String] = [:]
    ) async throws -> HelperResult {
        try await executeWithStreaming(
            command: command,
            workingDirectory: workingDirectory,
            environment: environment
        )
    }

    @discardableResult
    func executeWithStreaming(
        command: String,
        workingDirectory: String? = nil,
        environment: [String: String] = [:]
    ) async throws -> HelperResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.spawnStreaming(
                        command: command,
                        workingDirectory: workingDirectory,
                        environment: environment
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - posix_spawn + Pipe 实时读取

    private func spawnStreaming(
        command: String,
        workingDirectory: String?,
        environment: [String: String]
    ) throws -> HelperResult {
        let useHelper = FileManager.default.isExecutableFile(atPath: helperPath)

        var stdoutPipe: [Int32] = [0, 0]
        var stderrPipe: [Int32] = [0, 0]
        guard pipe(&stdoutPipe) == 0, pipe(&stderrPipe) == 0 else {
            throw HelperError.pipeFailed
        }

        // 构建 argv
        let executable: String
        let spawnArgs: [String]
        if useHelper {
            executable = helperPath
            if let wd = workingDirectory {
                spawnArgs = ["-w", wd, "-c", command]
            } else {
                spawnArgs = ["-c", command]
            }
        } else {
            executable = "/bin/sh"
            let wrapped: String
            if let wd = workingDirectory {
                wrapped = "cd \(PathSafety.shellQuote(wd)) && \(command)"
            } else {
                wrapped = command
            }
            spawnArgs = ["-c", wrapped]
        }

        let cArgs: [String] = [executable] + spawnArgs
        let argv: [UnsafeMutablePointer<CChar>?] = cArgs.map { strdup($0) } + [nil]
        defer { argv.forEach { if let p = $0 { free(p) } } }

        // 构建 envp
        var envDict = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        envDict["LANG"] = envDict["LANG"] ?? "C.UTF-8"
        envDict["PYTHONUNBUFFERED"] = "1"
        if let theos = envDict["THEOS"], !theos.isEmpty {
            envDict["PATH"] = "\(theos)/bin:/usr/local/bin:/usr/bin:/bin:\(envDict["PATH"] ?? "")"
        }
        let envp: [UnsafeMutablePointer<CChar>?] = envDict.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { envp.forEach { if let p = $0 { free(p) } } }

        // posix_spawn_file_actions：重定向 stdout/stderr 到 Pipe 写端
        let fileActionsPtr = UnsafeMutablePointer<posix_spawn_file_actions_t>.allocate(capacity: 1)
        defer {
            posix_spawn_file_actions_destroy(fileActionsPtr)
            fileActionsPtr.deallocate()
        }
        posix_spawn_file_actions_init(fileActionsPtr)

        posix_spawn_file_actions_addclose(fileActionsPtr, stdoutPipe[0])
        posix_spawn_file_actions_addclose(fileActionsPtr, stderrPipe[0])
        posix_spawn_file_actions_adddup2(fileActionsPtr, stdoutPipe[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(fileActionsPtr, stderrPipe[1], STDERR_FILENO)
        posix_spawn_file_actions_addclose(fileActionsPtr, stdoutPipe[1])
        posix_spawn_file_actions_addclose(fileActionsPtr, stderrPipe[1])

        // 关闭 stdin，防止 make 等待输入
        let devNull = open("/dev/null", O_RDONLY)
        if devNull >= 0 {
            posix_spawn_file_actions_adddup2(fileActionsPtr, devNull, STDIN_FILENO)
            posix_spawn_file_actions_addclose(fileActionsPtr, devNull)
        }

        let attrPtr = UnsafeMutablePointer<posix_spawnattr_t>.allocate(capacity: 1)
        defer {
            posix_spawnattr_destroy(attrPtr)
            attrPtr.deallocate()
        }
        posix_spawnattr_init(attrPtr)

        var pid: pid_t = 0
        let spawnResult: Int32 = argv.withUnsafeBufferPointer { argvBuf in
            envp.withUnsafeBufferPointer { envBuf in
                posix_spawn(
                    &pid,
                    executable,
                    fileActionsPtr,
                    attrPtr,
                    argvBuf.baseAddress,
                    envBuf.baseAddress
                )
            }
        }

        // 父进程关闭写端
        close(stdoutPipe[1])
        close(stderrPipe[1])
        if devNull >= 0 { close(devNull) }

        guard spawnResult == 0 else {
            close(stdoutPipe[0])
            close(stderrPipe[0])
            throw HelperError.spawnFailed(spawnResult)
        }

        // 设为非阻塞，便于双路复用读取
        try setNonBlocking(stdoutPipe[0])
        try setNonBlocking(stderrPipe[0])

        let stdoutBuffer = StreamLineBuffer()
        let stderrBuffer = StreamLineBuffer()
        var stdoutRaw = ""
        var stderrRaw = ""

        // 轮询读取直到进程退出且 Pipe 排空
        var status: Int32 = 0
        var processExited = false

        while !processExited || hasPendingData(stdoutPipe[0]) || hasPendingData(stderrPipe[0]) {
            if !processExited {
                let waitResult = waitpid(pid, &status, WNOHANG)
                if waitResult == pid {
                    processExited = true
                } else if waitResult < 0 {
                    processExited = true
                }
            }

            let outChunk = readAvailable(fd: stdoutPipe[0])
            if !outChunk.isEmpty {
                stdoutRaw += outChunk
                emitLines(outChunk, buffer: stdoutBuffer, stream: .stdout)
                onOutput?(outChunk, .stdout)
            }

            let errChunk = readAvailable(fd: stderrPipe[0])
            if !errChunk.isEmpty {
                stderrRaw += errChunk
                emitLines(errChunk, buffer: stderrBuffer, stream: .stderr)
                onOutput?(errChunk, .stderr)
            }

            if !processExited && outChunk.isEmpty && errChunk.isEmpty {
                usleep(10_000) // 10ms，避免空转占满 CPU
            }
        }

        // 刷新残余行
        flushBuffer(stdoutBuffer, stream: .stdout)
        flushBuffer(stderrBuffer, stream: .stderr)

        close(stdoutPipe[0])
        close(stderrPipe[0])

        if !processExited {
            waitpid(pid, &status, 0)
        }

        let exitCode = Self.decodeExitCode(from: status)
        return HelperResult(exitCode: exitCode, stdout: stdoutRaw, stderr: stderrRaw)
    }

    /// 解析 waitpid status（Swift 无法直接使用 WIFEXITED/WEXITSTATUS 宏）
    private static func decodeExitCode(from status: Int32) -> Int32 {
        if (status & 0x7F) == 0 {
            return (status >> 8) & 0xFF
        }
        return -1
    }

    // MARK: - IO Helpers

    private func setNonBlocking(_ fd: Int32) throws {
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0 else { throw HelperError.fcntlFailed }
        guard fcntl(fd, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            throw HelperError.fcntlFailed
        }
    }

    private func readAvailable(fd: Int32) -> String {
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: readBufferSize)
        defer { buffer.deallocate() }

        while true {
            let bytesRead = read(fd, buffer, readBufferSize)
            if bytesRead > 0 {
                data.append(buffer, count: bytesRead)
            } else {
                break
            }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func hasPendingData(_ fd: Int32) -> Bool {
        var pollfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let result = poll(&pollfd, 1, 0)
        return result > 0 && (pollfd.revents & Int16(POLLIN)) != 0
    }

    private func emitLines(_ chunk: String, buffer: StreamLineBuffer, stream: BuildLogEntry.Stream) {
        let lines = buffer.feed(chunk)
        for line in lines {
            onLine?(line, stream)
        }
    }

    private func flushBuffer(_ buffer: StreamLineBuffer, stream: BuildLogEntry.Stream) {
        if let tail = buffer.flush(), !tail.isEmpty {
            onLine?(tail, stream)
        }
    }
}
