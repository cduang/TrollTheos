import SwiftUI

/// 侧边栏文件树浏览器
struct FileTreeView: View {
    @ObservedObject var manager: FileTreeManager

    var body: some View {
        List {
            if let root = manager.rootNode {
                FileTreeNodeView(node: root, manager: manager, depth: 0)
            } else {
                Text("请选择 Tweak 项目文件夹")
                    .foregroundColor(.secondary)
            }
        }
        .listStyle(.sidebar)
    }
}

private struct FileTreeNodeView: View {
    @ObservedObject var node: ProjectFileNode
    @ObservedObject var manager: FileTreeManager
    let depth: Int

    var body: some View {
        if node.isDirectory {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { node.isExpanded },
                    set: { _ in manager.toggleExpand(node) }
                )
            ) {
                ForEach(node.children) { child in
                    FileTreeNodeView(node: child, manager: manager, depth: depth + 1)
                }
            } label: {
                Label(node.name, systemImage: "folder")
            }
        } else {
            Button {
                manager.selectFile(node)
            } label: {
                HStack {
                    Image(systemName: iconName)
                        .foregroundColor(iconColor)
                    Text(node.name)
                        .foregroundColor(.primary)
                }
            }
            .buttonStyle(.plain)
            .background(
                manager.selectedFile?.url == node.url
                    ? Color.accentColor.opacity(0.15)
                    : Color.clear
            )
        }
    }

    private var iconName: String {
        let ext = node.url.pathExtension.lowercased()
        switch ext {
        case "x", "xm": return "chevron.left.forwardslash.chevron.right"
        case "m", "mm", "h": return "doc.text"
        default:
            if node.name.lowercased() == "makefile" { return "gearshape" }
            return "doc"
        }
    }

    private var iconColor: Color {
        let ext = node.url.pathExtension.lowercased()
        if ext == "x" || ext == "xm" { return .orange }
        if node.name.lowercased() == "makefile" { return .blue }
        return .secondary
    }
}
