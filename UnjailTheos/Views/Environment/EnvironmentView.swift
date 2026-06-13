import SwiftUI
import UniformTypeIdentifiers

/// Module A: 环境初始化 — Theos 自动安装、SDK 下载、导入与解压
struct EnvironmentView: View {
    @EnvironmentObject private var theosInstaller: TheosInstaller
    @StateObject private var sdkManager = SDKManager()
    @State private var showImporter = false
    @AppStorage("com.unjailtheos.isProxyEnabled") private var isProxyEnabled = true

    var body: some View {
        NavigationView {
            List {
                networkSection
                theosSection
                onlineDownloadSection
                manualImportSection
                installedSDKSection
                statusSection
            }
            .navigationTitle("环境初始化")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        sdkManager.refreshInstalledSDKs()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.zip, .data, .gzip],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task { await sdkManager.importLocalArchive(from: url) }
                }
            case .failure(let error):
                sdkManager.statusMessage = error.localizedDescription
            }
        }
        .onAppear {
            NetworkConfig.isProxyEnabled = isProxyEnabled
            try? TheosPaths.ensureDirectoryStructure()
        }
        .onChange(of: isProxyEnabled) { newValue in
            NetworkConfig.isProxyEnabled = newValue
        }
    }

    private var networkSection: some View {
        Section {
            Toggle(isOn: $isProxyEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("GitHub 加速模式")
                        .font(.headline)
                    Text("使用 v4.gh-proxy.org 代理下载 Theos / SDK")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } footer: {
            Text("中国大陆用户建议开启，可避免首次下载 Theos 或 SDK 时长时间卡住。")
        }
    }

    private var theosSection: some View {
        Section("Theos 工具链") {
            HStack {
                theosStatusIcon
                VStack(alignment: .leading, spacing: 4) {
                    Text("THEOS")
                        .font(.headline)
                    Text(TheosPaths.theosRoot.path)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    if !theosInstaller.progressMessage.isEmpty {
                        Text(theosInstaller.progressMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if theosInstaller.state == .installing {
                    ProgressView()
                } else {
                    Button("重装") {
                        Task { await theosInstaller.installTheos(force: true) }
                    }
                    .disabled(theosInstaller.state == .installing)
                }
            }

            if theosInstaller.state == .installing && theosInstaller.downloadProgress.totalBytes > 0 {
                ProgressView(value: theosInstaller.downloadProgress.fraction) {
                    Text("Theos 下载进度")
                } currentValueLabel: {
                    Text(theosInstaller.downloadProgress.formattedProgress)
                }
            }
        }
    }

    @ViewBuilder
    private var theosStatusIcon: some View {
        switch theosInstaller.state {
        case .installed:
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .installing, .checking:
            Image(systemName: "arrow.down.circle").foregroundColor(.orange)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
        case .idle:
            Image(systemName: "questionmark.circle").foregroundColor(.secondary)
        }
    }

    private var onlineDownloadSection: some View {
        Section("在线 SDK 下载") {
            ForEach(SDKSource.predefined) { source in
                HStack {
                    VStack(alignment: .leading) {
                        Text(source.name)
                            .font(.headline)
                        Text(source.sdkFolderName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if sdkManager.isProcessing {
                        ProgressView()
                            .frame(width: 24)
                    } else {
                        Button("下载") {
                            Task { await sdkManager.downloadAndExtract(source: source) }
                        }
                        .disabled(sdkManager.isProcessing || theosInstaller.state == .installing)
                    }
                }
            }

            if sdkManager.isProcessing && !sdkManager.downloadProgress.phase.isEmpty {
                HStack {
                    ProgressView()
                    VStack(alignment: .leading) {
                        Text("SDK 拉取")
                        Text(sdkManager.downloadProgress.formattedProgress)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var manualImportSection: some View {
        Section("手动导入 SDK") {
            Button {
                showImporter = true
            } label: {
                Label("选择 .zip / .tar.xz 文件", systemImage: "square.and.arrow.down")
            }
            .disabled(sdkManager.isProcessing)

            Text("通过 Root Helper 调用 /usr/bin/tar 或 /usr/bin/unzip 解压，保留符号链接")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var installedSDKSection: some View {
        Section("已安装 SDK") {
            if sdkManager.installedSDKs.isEmpty {
                Text("暂无 SDK，请下载或导入")
                    .foregroundColor(.secondary)
            } else {
                ForEach(sdkManager.installedSDKs) { sdk in
                    HStack {
                        Image(systemName: "shippingbox")
                            .foregroundColor(.green)
                        VStack(alignment: .leading) {
                            Text(sdk.name)
                            Text(sdk.path.path)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            sdkManager.deleteSDK(sdk)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if let message = sdkManager.statusMessage {
            Section("状态") {
                Text(message)
                    .font(.callout)
            }
        }
    }
}
