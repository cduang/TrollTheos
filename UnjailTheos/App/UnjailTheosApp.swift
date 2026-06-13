import SwiftUI

@main
struct UnjailTheosApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var theosInstaller = TheosInstaller()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(theosInstaller)
                .task {
                    try? TheosPaths.ensureDirectoryStructure()
                    await theosInstaller.ensureTheosInstalledIfNeeded()
                    appState.theosRoot = TheosPaths.theosRoot
                }
        }
    }
}

/// 全局应用状态
final class AppState: ObservableObject {
    @Published var theosRoot: URL = TheosPaths.theosRoot
    @Published var projectRoot: URL?
    @Published var selectedTab: AppTab = .environment

    enum AppTab: String, CaseIterable, Identifiable {
        case environment = "环境"
        case editor = "编辑器"
        case build = "构建"
        case github = "云端构建"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .environment: return "gearshape.2"
            case .editor: return "doc.text"
            case .build: return "hammer"
            case .github: return "cloud"
            }
        }
    }
}
