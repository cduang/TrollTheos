import Foundation

/// 路径安全校验与 Shell 转义工具
enum PathSafety {
    enum ValidationError: LocalizedError {
        case pathTraversal
        case outsideAllowedRoot(URL)
        case archiveNotFound
        case destinationNotDirectory
        case invalidArchiveExtension(String)
        case symlinkEscape(URL)

        var errorDescription: String? {
            switch self {
            case .pathTraversal:
                return "路径包含非法 traversal 组件"
            case .outsideAllowedRoot(let url):
                return "路径超出允许范围: \(url.path)"
            case .archiveNotFound:
                return "压缩包不存在"
            case .destinationNotDirectory:
                return "目标路径不是有效目录"
            case .invalidArchiveExtension(let ext):
                return "不支持的压缩格式: .\(ext)"
            case .symlinkEscape(let url):
                return "路径解析后逃逸允许目录: \(url.path)"
            }
        }
    }

    /// 允许操作文件的根目录（App Documents）
    static var allowedRoot: URL {
        TheosPaths.documentsDirectory.standardizedFileURL
    }

    /// POSIX shell 单引号转义，防止命令注入
    static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// 解析并校验路径必须在 allowedRoot 之下
    static func validatedPath(_ url: URL, mustExist: Bool = true) throws -> URL {
        let standardized = url.standardizedFileURL
        let resolved = try resolveWithoutSymlinkEscape(standardized)

        guard isContained(resolved, in: allowedRoot) else {
            throw ValidationError.outsideAllowedRoot(resolved)
        }

        let components = resolved.pathComponents
        if components.contains("..") {
            throw ValidationError.pathTraversal
        }

        if mustExist && !FileManager.default.fileExists(atPath: resolved.path) {
            throw ValidationError.archiveNotFound
        }

        return resolved
    }

    /// 校验解压目标目录
    static func validatedDestination(_ url: URL) throws -> URL {
        let resolved = try validatedPath(url, mustExist: false)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir)

        if exists && !isDir.boolValue {
            throw ValidationError.destinationNotDirectory
        }
        if !exists {
            try FileManager.default.createDirectory(at: resolved, withIntermediateDirectories: true)
        }
        return resolved
    }

    /// 判断压缩包类型
    static func archiveKind(for url: URL) -> ArchiveKind {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".tar.xz") || name.hasSuffix(".txz") {
            return .tarXz
        }
        if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") {
            return .tarGz
        }
        if name.hasSuffix(".tar") {
            return .tar
        }
        if name.hasSuffix(".zip") {
            return .zip
        }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "xz": return .tarXz
        case "zip": return .zip
        case "tar": return .tar
        case "gz": return .tarGz
        default: return .unknown(ext)
        }
    }

    enum ArchiveKind {
        case zip
        case tar
        case tarGz
        case tarXz
        case unknown(String)

        var isSupported: Bool {
            switch self {
            case .unknown: return false
            default: return true
            }
        }
    }

    // MARK: - Private

    private static func isContained(_ child: URL, in parent: URL) -> Bool {
        let childPath = child.standardizedFileURL.path
        let parentPath = parent.standardizedFileURL.path
        return childPath == parentPath || childPath.hasPrefix(parentPath + "/")
    }

    /// 解析路径并确保 symlink 不会逃逸 allowedRoot
    private static func resolveWithoutSymlinkEscape(_ url: URL) throws -> URL {
        let fm = FileManager.default
        var current = url.path == "/" ? url : url.deletingLastPathComponent()
        var remaining = url.lastPathComponent

        if url.hasDirectoryPath || url.path.hasSuffix("/") {
            // 目录 URL
        } else if remaining.isEmpty {
            remaining = ""
        }

        if url.path == "/" {
            return url
        }

        // 逐层解析
        var builtPath = ""
        let parts = url.standardizedFileURL.pathComponents.filter { $0 != "/" }
        builtPath = "/"

        for (index, part) in parts.enumerated() {
            builtPath = (builtPath as NSString).appendingPathComponent(part)
            let probe = URL(fileURLWithPath: builtPath)

            if fm.fileExists(atPath: builtPath) {
                let attrs = try fm.attributesOfItem(atPath: builtPath)
                if attrs[.type] as? FileAttributeType == .typeSymbolicLink {
                    let dest = probe.resolvingSymlinksInPath()
                    guard isContained(dest, in: allowedRoot) else {
                        throw ValidationError.symlinkEscape(dest)
                    }
                    builtPath = dest.path
                }
            }

            if index == parts.count - 1 {
                return URL(fileURLWithPath: builtPath)
            }
        }

        return URL(fileURLWithPath: builtPath)
    }
}
