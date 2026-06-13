import SwiftUI
import UniformTypeIdentifiers

/// Module B: 代码编辑器 GUI
struct EditorView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var fileManager = FileTreeManager()
    @State private var showProjectPicker = false

    var body: some View {
        NavigationView {
            FileTreeView(manager: fileManager)
                .frame(minWidth: 220)
                .navigationTitle("项目文件")

            editorDetail
        }
        .navigationViewStyle(DoubleColumnNavigationViewStyle())
        .fileImporter(
            isPresented: $showProjectPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    let didStart = url.startAccessingSecurityScopedResource()
                    fileManager.loadProject(at: url)
                    appState.projectRoot = url
                    if didStart { url.stopAccessingSecurityScopedResource() }
                }
            case .failure(let error):
                fileManager.errorMessage = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private var editorDetail: some View {
        if let selected = fileManager.selectedFile {
            VStack(spacing: 0) {
                HStack {
                    Text(selected.url.lastPathComponent)
                        .font(.headline)
                    Spacer()
                    Button("保存") {
                        fileManager.saveCurrentFile()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))

                CodeEditorView(
                    text: $fileManager.fileContent,
                    language: selected.syntaxLanguage,
                    onSave: { fileManager.saveCurrentFile() }
                )
            }
            .navigationTitle(selected.name)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("选择 Tweak 项目文件夹开始编辑")
                    .foregroundColor(.secondary)
                Button("打开项目") {
                    showProjectPicker = true
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("打开项目") {
                        showProjectPicker = true
                    }
                }
            }
        }
    }
}
