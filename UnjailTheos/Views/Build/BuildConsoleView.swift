import SwiftUI

/// Module C: Root Helper 构建执行与日志控制台
struct BuildConsoleView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var executor = BuildExecutor()
    @State private var showProjectPicker = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                buildControlBar
                Divider()
                logConsole
            }
            .navigationTitle("本地构建")
        }
        .navigationViewStyle(.stack)
        .fileImporter(
            isPresented: $showProjectPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                appState.projectRoot = url
            }
        }
    }

    private var buildControlBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("项目路径")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(appState.projectRoot?.path ?? "未选择项目")
                        .font(.footnote)
                        .lineLimit(2)
                }
                Spacer()
                Button("选择项目") { showProjectPicker = true }
                    .buttonStyle(.bordered)
            }

            HStack {
                stateIndicator
                Spacer()
                if executor.state.isRunning {
                    Button("取消") { executor.cancel() }
                        .buttonStyle(.bordered)
                        .tint(.red)
                } else {
                    Button("清空日志") { executor.clearLogs() }
                        .buttonStyle(.bordered)
                }
                Button("make package") { startBuild() }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.projectRoot == nil || executor.state.isRunning)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch executor.state {
        case .idle:
            Label("就绪", systemImage: "circle")
                .foregroundColor(.secondary)
        case .running:
            Label("构建中...", systemImage: "arrow.triangle.2.circlepath")
                .foregroundColor(.orange)
        case .succeeded:
            Label("构建成功", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed(_, let message):
            Label("构建失败", systemImage: "xmark.circle.fill")
                .foregroundColor(.red)
                .help(message)
        }
    }

    private var logConsole: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(executor.logs) { entry in
                        Text(entry.displayText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(color(for: entry.stream))
                            .id(entry.id)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.systemBackground))
            .onChange(of: executor.logs.count) { _ in
                scrollToLatest(in: proxy)
            }
            .onAppear {
                scrollToLatest(in: proxy)
            }
        }
    }

    private func color(for stream: BuildLogEntry.Stream) -> Color {
        switch stream {
        case .stdout: return .primary
        case .stderr: return .red
        case .system: return .blue
        }
    }

    private func startBuild() {
        guard let project = appState.projectRoot else { return }
        executor.build(projectPath: project, theosPath: appState.theosRoot)
    }

    private func scrollToLatest(in proxy: ScrollViewProxy) {
        if let last = executor.logs.last {
            withAnimation {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}
