import SwiftUI

@main
struct FitStatsApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .tint(Theme.recoveryGreen)
                .onOpenURL { url in model.handleCallback(url) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await model.refreshAll() } }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.appKey == nil {
                ConnectView()
            } else {
                MainTabs()
            }
        }
        .background(Theme.background.ignoresSafeArea())
    }
}

struct MainTabs: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "circle.circle.fill") }
            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
            InsightsView()
                .tabItem { Label("Insights", systemImage: "sparkles") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .task { await model.refreshAll(force: true) }
    }
}
