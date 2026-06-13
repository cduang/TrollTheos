import Foundation

/// Theos 相关路径常量
enum TheosPaths {
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    static var theosRoot: URL {
        documentsDirectory.appendingPathComponent("theos", isDirectory: true)
    }

    static var sdksDirectory: URL {
        theosRoot.appendingPathComponent("sdks", isDirectory: true)
    }

    static var cacheDirectory: URL {
        theosRoot.appendingPathComponent("cache", isDirectory: true)
    }

    static var rootHelperBinary: URL {
        Bundle.main.bundleURL.appendingPathComponent("roothelper")
    }

    /// 检测 Theos 工具链是否完整安装
    static func isTheosInstalled() -> Bool {
        let fm = FileManager.default
        let makefile = theosRoot.appendingPathComponent("Makefile")
        let nic = theosRoot.appendingPathComponent("bin/nic.pl")
        let logos = theosRoot.appendingPathComponent("bin/logos.pl")
        return fm.fileExists(atPath: makefile.path)
            && fm.fileExists(atPath: nic.path)
            && fm.fileExists(atPath: logos.path)
    }

    /// 确保 Theos 目录结构存在
    static func ensureDirectoryStructure() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: sdksDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}
