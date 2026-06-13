#!/usr/bin/env swift

import Foundation
import Darwin

/// POSIX shell 单引号转义
func shellSingleQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// Root Helper 入口
///
/// 通过 exec 替换当前进程为 /bin/sh，stdout/stderr 直接继承主应用 posix_spawn 建立的 Pipe，
/// 子进程输出不经内部缓冲，BuildConsoleView 可实时收到 make package 日志。
///
/// 用法: roothelper -c "shell command"
/// 可选: roothelper -w /path/to/cwd -c "shell command"

enum HelperExit: Int32 {
    case usage = 1
    case execFailed = 127
}

func printUsage() {
    fputs("Usage: roothelper [-w workdir] -c \"command\"\n", stderr)
}

// 解析命令行参数
var workdir: String?
var command: String?
var i = 1
while i < CommandLine.arguments.count {
    let arg = CommandLine.arguments[i]
    switch arg {
    case "-w":
        i += 1
        guard i < CommandLine.arguments.count else {
            printUsage()
            exit(HelperExit.usage.rawValue)
        }
        workdir = CommandLine.arguments[i]
    case "-c":
        i += 1
        guard i < CommandLine.arguments.count else {
            printUsage()
            exit(HelperExit.usage.rawValue)
        }
        command = CommandLine.arguments[i]
    default:
        printUsage()
        exit(HelperExit.usage.rawValue)
    }
    i += 1
}

guard let shellCommand = command else {
    printUsage()
    exit(HelperExit.usage.rawValue)
}

// 组装最终 shell 脚本：可选 cd + 用户命令
let finalCommand: String
if let wd = workdir {
    finalCommand = "cd \(shellSingleQuote(wd)) && \(shellCommand)"
} else {
    finalCommand = shellCommand
}

// 配置环境变量（THEOS / PATH / 无缓冲 IO）
var env = ProcessInfo.processInfo.environment
if let theos = env["THEOS"], !theos.isEmpty {
    let theosBin = "\(theos)/bin"
    env["PATH"] = "\(theosBin):/usr/local/bin:/usr/bin:/bin:\(env["PATH"] ?? "")"
}
env["LANG"] = env["LANG"] ?? "C.UTF-8"
env["PYTHONUNBUFFERED"] = "1"

for (key, value) in env {
    setenv(key, value, 1)
}

// 关闭 stdin，避免意外交互阻塞
let devNull = open("/dev/null", O_RDONLY)
if devNull >= 0 {
    dup2(devNull, STDIN_FILENO)
    close(devNull)
}

let argv: [UnsafeMutablePointer<CChar>?] = [
    strdup("/bin/sh"),
    strdup("-c"),
    strdup(finalCommand),
    nil
]
defer { argv.forEach { if let ptr = $0 { free(ptr) } } }

// exec 替换当前进程，stdout/stderr FD 继承自主应用 Pipe
execv("/bin/sh", argv)

// exec 失败才会执行到这里
let errnoCode = errno
fputs("roothelper execv failed (\(errnoCode)): \(String(cString: strerror(errnoCode)))\n", stderr)
exit(HelperExit.execFailed.rawValue)
