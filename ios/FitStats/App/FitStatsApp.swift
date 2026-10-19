import SwiftUI
import UserNotifications

@main
struct FitStatsApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var live = LiveHeartRateMonitor()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UNUserNotificationCenter.current().delegate = ReminderDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.coach)
                .environmentObject(live)
                .preferredColorScheme(.dark)
                .tint(Theme.recoveryGreen)
                .onOpenURL { url in model.handleCallback(url) }
                .onAppear {
                    ReminderDelegate.shared.onOpen = { [model] route in
                        if route == "journal" { model.journalRequest = model.today }
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        live.resume()
                        Task { await model.refreshAll() }
                    } else if phase == .background {
                        live.pause()
                    }
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
    @State private var tab = "today"

    var body: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "circle.circle.fill") }
                .tag("today")
            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
                .tag("trends")
            CoachView()
                .tabItem { Label("Coach", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag("coach")
            InsightsView()
                .tabItem { Label("Insights", systemImage: "sparkles") }
                .tag("insights")
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag("settings")
        }
        .task { await model.refreshAll(force: true) }
        // A tapped journal reminder opens Today, which shows the journal.
        .onChange(of: model.journalRequest) { _, day in
            if day != nil { tab = "today" }
        }
    }
}
