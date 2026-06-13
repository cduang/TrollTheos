import Foundation

/// Tweak 项目文件树管理
@MainActor
final class FileTreeManager: ObservableObject {
    @Published var rootNode: ProjectFileNode?
    @Published var selectedFile: ProjectFileNode?
    @Published var fileContent: String = ""
    @Published var errorMessage: String?

    private var projectRoot: URL?

    func loadProject(at url: URL) {
        projectRoot = url
        rootNode = ProjectFileNode(url: url)
        loadChildren(for: rootNode!)
        selectedFile = nil
        fileContent = ""
        errorMessage = nil
    }

    func selectFile(_ node: ProjectFileNode) {
        guard node.isEditableSource else { return }
        selectedFile = node
        loadFileContent(from: node.url)
    }

    func saveCurrentFile() {
        guard let url = selectedFile?.url else { return }
        do {
            try fileContent.write(to: url, atomically: true, encoding: .utf8)
            errorMessage = nil
        } catch {
            errorMessage = "保存失败: \(error.localizedDescription)"
        }
    }

    func toggleExpand(_ node: ProjectFileNode) {
        node.isExpanded.toggle()
        if node.isExpanded && node.children.isEmpty {
            loadChildren(for: node)
        }
    }

    private func loadChildren(for node: ProjectFileNode) {
        guard node.isDirectory else { return }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: node.url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let sorted = contents.sorted { a, b in
            let aIsDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let bIsDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if aIsDir != bIsDir { return aIsDir }
            return a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent) == .orderedAscending
        }

        node.children = sorted.map { ProjectFileNode(url: $0) }
    }

    private func loadFileContent(from url: URL) {
        do {
            fileContent = try String(contentsOf: url, encoding: .utf8)
            errorMessage = nil
        } catch {
            fileContent = ""
            errorMessage = "无法读取文件: \(error.localizedDescription)"
        }
    }
}
