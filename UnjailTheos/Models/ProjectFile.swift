import Foundation

/// 项目文件树节点
final class ProjectFileNode: Identifiable, ObservableObject, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    @Published var children: [ProjectFileNode] = []
    @Published var isExpanded: Bool = false

    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        self.isDirectory = isDir.boolValue
    }

    static func == (lhs: ProjectFileNode, rhs: ProjectFileNode) -> Bool {
        lhs.url == rhs.url
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    /// 是否支持语法高亮的源文件
    var isEditableSource: Bool {
        guard !isDirectory else { return false }
        let ext = url.pathExtension.lowercased()
        return ["x", "xm", "m", "mm", "h", "plist", "makefile"].contains(ext)
            || name.lowercased() == "makefile"
    }

    var syntaxLanguage: SyntaxLanguage {
        let ext = url.pathExtension.lowercased()
        if ext == "x" || ext == "xm" { return .logos }
        if name.lowercased() == "makefile" || ext == "makefile" { return .makefile }
        return .plain
    }
}

/// 语法高亮语言类型
enum SyntaxLanguage: String {
    case logos
    case makefile
    case plain
}
