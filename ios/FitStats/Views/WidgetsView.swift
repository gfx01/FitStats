import SwiftUI

/// Settings → Widgets: what the Home Screen widgets look like with today's numbers, whether the
/// app can share them with the widgets after your signing app signed it, and how to add one.
struct WidgetsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var working: Bool?

    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    pair("Scores", "Sleep") { WidgetScoresSmall(snapshot: snapshot) } right: { WidgetSleepSmall(snapshot: snapshot) }
                    pair("Steps", "Heart") { WidgetStepsSmall(snapshot: snapshot) } right: { WidgetHeartSmall(snapshot: snapshot) }
                    pair("Stress", "Training") { WidgetStressSmall(snapshot: snapshot) } right: { WidgetTrainingSmall(snapshot: snapshot) }
                    named("Scores") { tile(width: 330) { WidgetScoresMedium(snapshot: snapshot) } }
                    named("Week") { tile(width: 330) { WidgetWeekMedium(snapshot: snapshot) } }
                    named("Coach") { tile(width: 330) { WidgetCoachFace(snapshot: snapshot, lines: 5) } }
                    named("Today") { tile(width: 330, height: 345) { WidgetTodayLarge(snapshot: snapshot) } }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("widget-previews")
            } footer: {
                Text("Nine widgets for the Home Screen. Scores, Sleep, Steps and Stress also come in Lock Screen sizes. Tapping a widget opens its part of the app.")
            }

            Section {
                HStack {
                    Text("Sharing with widgets")
                    Spacer()
                    switch working {
                    case true?:
                        Label("Working", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.recoveryGreen)
                    case false?:
                        Label("Not available", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.recoveryYellow)
                    case nil:
                        ProgressView()
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("widget-sharing")
                KeyValueRow(key: "App group", value: SharedStore.groupID)
            } header: {
                Text("Status")
            } footer: {
                Text(statusText)
            }

            Section("Add a widget") {
                step(1, "Touch and hold an empty spot on your Home Screen until the apps jiggle.")
                step(2, "Tap Edit in the top-left corner, then Add Widget.")
                step(3, "Search for FitStats, pick Scores or Sleep, choose a size and tap Add Widget.")
                step(4, "For the Lock Screen: touch and hold the Lock Screen, tap Customize, then the box under the time.")
            }
        }
        .screenBackground()
        .navigationTitle("Widgets")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            working = model.isFixture ? true : SharedStore.isWorking()
            model.updateWidgets()
        }
    }

    /// Today's numbers as the widgets will show them (an empty day before today has loaded).
    private var snapshot: WidgetSnapshot {
        model.widgetSnapshot() ?? WidgetSnapshot(date: model.today, updated: Date(), row: [:])
    }

    private func pair(_ leftName: String, _ rightName: String, @ViewBuilder _ left: () -> some View,
                      @ViewBuilder right: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 14) {
            named(leftName) { tile(width: 158) { left() } }
            named(rightName) { tile(width: 158) { right() } }
        }
    }

    /// A preview with the widget's name under it, as in the widget gallery.
    private func named(_ name: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 5) {
            content()
            Text(name).font(.caption2.weight(.medium)).foregroundStyle(Theme.secondary)
        }
    }

    private var statusText: String {
        switch working {
        case true?:
            return "The widgets read today's numbers from the app and refresh themselves from your server about every 30 minutes. Opening the app updates them at once."
        case false?:
            return "Your signing app didn't give FitStats an app group, so the widgets can't see the app's data and will ask you to open the app. In your signing app, turn on app groups (sometimes called \"keep extensions\" or \"app group support\") and sign FitStats again. The widget needs one more App ID on a free Apple ID."
        case nil:
            return " "
        }
    }

    private func tile(width: CGFloat, height: CGFloat = 158, @ViewBuilder _ content: () -> some View) -> some View {
        content()
            .padding(14)
            .frame(width: width, height: height)
            .background(WidgetBackground())
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.cardBorder))
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.black)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Theme.recoveryGreen))
            Text(text).font(.subheadline)
        }
    }
}
