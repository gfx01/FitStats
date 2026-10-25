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
                    HStack(spacing: 14) {
                        tile(width: 158) { WidgetScoresSmall(snapshot: snapshot) }
                        tile(width: 158) { WidgetSleepSmall(snapshot: snapshot) }
                    }
                    tile(width: 330) { WidgetScoresMedium(snapshot: snapshot) }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("widget-previews")
            } footer: {
                Text("Scores and Sleep, for the Home Screen. Both also come in Lock Screen sizes.")
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

    /// Today's numbers as the widgets will show them.
    private var snapshot: WidgetSnapshot {
        let date = model.today
        let plan = SleepPlan.plan(days: model.daysByDate, today: date,
                                  sleepNeedMin: Double(model.status?.settings.sleepNeedMin ?? 480), wakeTimes: model.wakeTimes)
        let row = model.daysByDate[date]?.values.mapValues { $0.anyValue } ?? [:]
        return WidgetSnapshot(date: date, updated: Date(), row: row,
                              bedtimeMin: plan.bedtimeMin, bedtimeFor: date)
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

    private func tile(width: CGFloat, @ViewBuilder _ content: () -> some View) -> some View {
        content()
            .padding(14)
            .frame(width: width, height: 158)
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
