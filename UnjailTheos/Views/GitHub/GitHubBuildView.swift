import SwiftUI

/// GitHub Actions 云端构建
struct GitHubBuildView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var gitManager = GitManager()
    @State private var showProjectPicker = false
    @State private var showToken = false
    @AppStorage("com.unjailtheos.isProxyEnabled") private var isProxyEnabled = true

    var body: some View {
        NavigationView {
            Form {
                networkSection
                projectSection
                credentialsSection
                actionSection
                logSection
            }
            .navigationTitle("云端构建")
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
        .onAppear {
            NetworkConfig.isProxyEnabled = isProxyEnabled
        }
        .onChange(of: isProxyEnabled) { newValue in
            NetworkConfig.isProxyEnabled = newValue
        }
    }

    private var networkSection: some View {
        Section {
            Toggle(isOn: $isProxyEnabled) {
                Label("GitHub 加速模式", systemImage: "bolt.horizontal.circle")
            }
        } footer: {
            Text("加速模式仅影响 App 内 Theos/SDK 下载，Git push 仍直连 GitHub。")
        }
    }

    private var projectSection: some View {
        Section("项目") {
            HStack {
                Text(appState.projectRoot?.lastPathComponent ?? "未选择")
                Spacer()
                Button("选择") { showProjectPicker = true }
            }
            if let path = appState.projectRoot?.path {
                Text(path)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var credentialsSection: some View {
        Section("GitHub 配置") {
            TextField("仓库 URL (https://github.com/user/repo)", text: $gitManager.config.repositoryURL)
                .textContentType(.URL)
                .autocapitalization(.none)
                .disableAutocorrection(true)

            TextField("分支", text: $gitManager.config.branch)
                .autocapitalization(.none)

            HStack {
                if showToken {
                    TextField("Personal Access Token", text: $gitManager.config.token)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                } else {
                    SecureField("Personal Access Token", text: $gitManager.config.token)
                }
                Button {
                    showToken.toggle()
                } label: {
                    Image(systemName: showToken ? "eye.slash" : "eye")
                }
            }

            TextField("作者名", text: $gitManager.config.authorName)
            TextField("作者邮箱", text: $gitManager.config.authorEmail)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
        }
    }

    private var actionSection: some View {
        Section {
            Button {
                guard let project = appState.projectRoot else {
                    gitManager.statusMessage = "请先选择项目"
                    return
                }
                Task { await gitManager.pushAndBuild(projectPath: project) }
            } label: {
                HStack {
                    if gitManager.isWorking {
                        ProgressView()
                            .padding(.trailing, 4)
                    }
                    Label("Push to GitHub & Build", systemImage: "cloud.upload")
                }
            }
            .disabled(appState.projectRoot == nil || gitManager.isWorking)

            if let status = gitManager.statusMessage {
                Text(status)
                    .font(.callout)
                    .foregroundColor(status.contains("失败") || status.contains("错误") ? .red : .green)
            }

            if let actionsURL = gitManager.lastReleaseURL {
                Link("查看 GitHub Actions 构建进度", destination: URL(string: actionsURL)!)
            }
        } footer: {
            Text("""
            流程：生成 build.yml → git init → commit → push → 触发 workflow_dispatch。
            编译成功后可在 GitHub Releases 下载 .deb 包。
            """)
        }
    }

    @ViewBuilder
    private var logSection: some View {
        if !gitManager.lastPushLog.isEmpty {
            Section("推送日志") {
                ScrollView {
                    Text(gitManager.lastPushLog)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 240)
            }
        }
    }
}
