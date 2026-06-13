import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            ForEach(AppState.AppTab.allCases) { tab in
                tabContent(for: tab)
                    .tabItem {
                        Label(tab.rawValue, systemImage: tab.systemImage)
                    }
                    .tag(tab)
            }
        }
    }

    @ViewBuilder
    private func tabContent(for tab: AppState.AppTab) -> some View {
        switch tab {
        case .environment:
            EnvironmentView()
        case .editor:
            EditorView()
        case .build:
            BuildConsoleView()
        case .github:
            GitHubBuildView()
        }
    }
}
