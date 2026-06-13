import Foundation

/// 通过 Root Helper 调用系统 /usr/bin/tar 或 /usr/bin/unzip 解压
///
/// iOS SDK 含大量符号链接，必须使用系统 tar（-x 保留 symlink），
/// 禁止使用 Swift Zip 库或 FileManager 解压。
final class ArchiveExtractor {
    enum ExtractError: LocalizedError {
        case invalidArchive(String)
        case invalidDestination(String)
        case unsupportedFormat(String)
        case toolMissing(String)
        case extractionFailed(exitCode: Int32, log: String)

        var errorDescription: String? {
            switch self {
            case .invalidArchive(let msg): return "压缩包校验失败: \(msg)"
            case .invalidDestination(let msg): return "目标路径校验失败: \(msg)"
            case .unsupportedFormat(let ext): return "不支持的格式: .\(ext)"
            case .toolMissing(let tool): return "系统工具不可用: \(tool)"
            case .extractionFailed(let code, let log):
                return "解压失败 (exit \(code)): \(log)"
            }
        }
    }

    private let rootHelper = RootHelperClient()
    private let tarPath = "/usr/bin/tar"
    private let unzipPath = "/usr/bin/unzip"

    /// 解压压缩包到目标目录
    func extract(archiveURL: URL, destination: URL) async throws {
        let archive = try validateArchive(archiveURL)
        let dest = try validateDestination(destination)
        let kind = PathSafety.archiveKind(for: archive)

        guard kind.isSupported else {
            if case .unknown(let ext) = kind {
                throw ExtractError.unsupportedFormat(ext)
            }
            throw ExtractError.unsupportedFormat("unknown")
        }

        let command = try buildExtractCommand(archive: archive, destination: dest, kind: kind)

        rootHelper.onLine = nil
        var logLines: [String] = []
        rootHelper.onLine = { line, stream in
            let prefix = stream == .stderr ? "[stderr] " : ""
            logLines.append(prefix + line)
        }

        let result = try await rootHelper.execute(
            command: command,
            workingDirectory: dest.path
        )

        guard result.exitCode == 0 else {
            let log = logLines.joined(separator: "\n")
            let fallback = result.stderr.isEmpty ? result.stdout : result.stderr
            throw ExtractError.extractionFailed(
                exitCode: result.exitCode,
                log: log.isEmpty ? fallback : log
            )
        }
    }

    // MARK: - 命令构建

    private func buildExtractCommand(
        archive: URL,
        destination: URL,
        kind: PathSafety.ArchiveKind
    ) throws -> String {
        let archiveQ = PathSafety.shellQuote(archive.path)
        let destQ = PathSafety.shellQuote(destination.path)

        switch kind {
        case .zip:
            guard FileManager.default.isExecutableFile(atPath: unzipPath) else {
                throw ExtractError.toolMissing(unzipPath)
            }
            // -o 覆盖；-d 指定目录
            return """
            set -e; \
            mkdir -p \(destQ) && \
            \(PathSafety.shellQuote(unzipPath)) -o \(archiveQ) -d \(destQ)
            """

        case .tar:
            guard FileManager.default.isExecutableFile(atPath: tarPath) else {
                throw ExtractError.toolMissing(tarPath)
            }
            // -x 解压 -v 详细 -f 文件，保留 symlink
            return """
            set -e; \
            mkdir -p \(destQ) && \
            cd \(destQ) && \
            \(PathSafety.shellQuote(tarPath)) -xvf \(archiveQ)
            """

        case .tarGz:
            guard FileManager.default.isExecutableFile(atPath: tarPath) else {
                throw ExtractError.toolMissing(tarPath)
            }
            return """
            set -e; \
            mkdir -p \(destQ) && \
            cd \(destQ) && \
            \(PathSafety.shellQuote(tarPath)) -xzvf \(archiveQ)
            """

        case .tarXz:
            guard FileManager.default.isExecutableFile(atPath: tarPath) else {
                throw ExtractError.toolMissing(tarPath)
            }
            // Theos SDK 标准格式：.tar.xz
            return """
            set -e; \
            mkdir -p \(destQ) && \
            cd \(destQ) && \
            \(PathSafety.shellQuote(tarPath)) -xJvf \(archiveQ)
            """

        case .unknown(let ext):
            throw ExtractError.unsupportedFormat(ext)
        }
    }

    // MARK: - 路径校验

    private func validateArchive(_ url: URL) throws -> URL {
        do {
            let resolved = try PathSafety.validatedPath(url, mustExist: true)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir),
                  !isDir.boolValue else {
                throw ExtractError.invalidArchive("不是有效文件")
            }

            let attrs = try FileManager.default.attributesOfItem(atPath: resolved.path)
            if let size = attrs[.size] as? Int64, size == 0 {
                throw ExtractError.invalidArchive("文件大小为 0")
            }

            guard PathSafety.archiveKind(for: resolved).isSupported else {
                throw ExtractError.unsupportedFormat(resolved.pathExtension)
            }

            return resolved
        } catch let error as PathSafety.ValidationError {
            throw ExtractError.invalidArchive(error.localizedDescription)
        }
    }

    private func validateDestination(_ url: URL) throws -> URL {
        do {
            // 解压目标必须在 Documents/theos/ 子树内
            let resolved = try PathSafety.validatedDestination(url)
            let theosRoot = TheosPaths.theosRoot.standardizedFileURL
            let childPath = resolved.standardizedFileURL.path
            let parentPath = theosRoot.path
            guard childPath == parentPath || childPath.hasPrefix(parentPath + "/") else {
                throw ExtractError.invalidDestination("目标必须在 Documents/theos/ 目录下")
            }
            return resolved
        } catch let error as PathSafety.ValidationError {
            throw ExtractError.invalidDestination(error.localizedDescription)
        }
    }
}
