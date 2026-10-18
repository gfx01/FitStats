import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var coach: CoachStore
    @State private var draft = UserSettings.defaults
    @State private var coachModel = ""
    @State private var useMaxHr = false
    @State private var saving = false
    @State private var exportURL: URL?
    @State private var confirmDisconnect = false
    @State private var confirmWipe = false

    private let historyOptions = [90, 180, 365, 730, 1095, 1825, 3650]

    var body: some View {
        NavigationStack {
            List {
                accountSection
                syncSection
                deviceSection
                preferencesSection
                coachSection
                dataSection
                dangerSection
                aboutSection
            }
            .screenBackground()
            .navigationTitle("Settings")
            .onAppear(perform: loadDraft)
            .onChange(of: model.status?.settings) { _, _ in loadDraft() }
            .task { if coach.status == nil { await coach.refresh() } }
            .onChange(of: coach.status?.model) { _, new in coachModel = new ?? "" }
            .confirmationDialog("Disconnect Google?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) { Task { await model.disconnect(wipe: false) } }
            } message: {
                Text("The server stops syncing and this app signs out. Your stored history is kept.")
            }
            .confirmationDialog("Delete all data?", isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { Task { await model.disconnect(wipe: true) } }
            } message: {
                Text("Removes every synced day, sleep and workout, your journal and coach chats, and the Google connection from your Supabase database. This cannot be undone.")
            }
        }
    }

    private func loadDraft() {
        guard let s = model.status?.settings else { return }
        draft = s
        useMaxHr = s.maxHrOverride != nil
    }

    // MARK: sections

    @ViewBuilder private var coachSection: some View {
        Section("Coach") {
            if let status = coach.status {
                KeyValueRow(key: "Claude API key", value: status.configured ? "Added" : "Missing",
                            color: status.configured ? Theme.recoveryGreen : Theme.recoveryYellow)
                Picker("Model", selection: $coachModel) {
                    ForEach(status.models) { m in Text(m.label).tag(m.id) }
                }
                .onChange(of: coachModel) { _, new in
                    guard !new.isEmpty, new != coach.status?.model else { return }
                    Task { await coach.setModel(new) }
                }
                if let note = status.models.first(where: { $0.id == coachModel })?.note {
                    Text(note).font(.caption).foregroundStyle(Theme.tertiary)
                }
                if let u = status.usage {
                    KeyValueRow(key: "This month", value: "\(u.requests) API calls · \(costText(u.costUsd))")
                    KeyValueRow(key: "Tokens", value: "\(Format.number(Double(u.input + u.cacheRead + u.cacheWrite))) in · \(Format.number(Double(u.output))) out")
                }
                Text("Cost is estimated from Anthropic's list prices; the Anthropic Console shows your actual bill. The coach answers at most \(status.dailyLimit ?? 100) messages a day.")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiary)
            } else {
                Text("Loading…").foregroundStyle(Theme.secondary)
            }
        }
        .onAppear { coachModel = coach.status?.model ?? "" }
    }

    private func costText(_ usd: Double) -> String {
        if usd > 0 && usd < 0.01 { return "under $0.01" }
        return String(format: "$%.2f", usd)
    }

    private var accountSection: some View {
        Section("Google Health") {
            KeyValueRow(key: "Account", value: model.status?.connection.email ?? "–")
            KeyValueRow(key: "Status", value: connectionText, color: connectionColor)
            if let missing = model.status?.connection.missingScopes, !missing.isEmpty {
                Text("Missing permissions: \(missing.joined(separator: ", "))")
                    .font(.footnote)
                    .foregroundStyle(Theme.recoveryYellow)
            }
            if let error = model.status?.connection.error, model.needsReconnect {
                Text(error).font(.caption).foregroundStyle(Theme.tertiary)
            }
            Button(model.needsReconnect ? "Reconnect Google" : "Re-authorise Google") {
                Task { await model.connect() }
            }
        }
    }

    private var connectionText: String {
        switch model.status?.connection.status {
        case "ok": return "Connected"
        case "expired": return "Expired — reconnect"
        case "error": return "Error"
        case "disconnected": return "Disconnected"
        default: return "Unknown"
        }
    }

    private var connectionColor: Color {
        model.status?.connection.status == "ok" ? Theme.recoveryGreen : Theme.recoveryRed
    }

    private var syncSection: some View {
        Section("Sync") {
            KeyValueRow(key: "Updated from Google", value: Format.relative(model.status?.sync.lastRecentSyncAt))
            KeyValueRow(key: "Last run", value: "\(Format.relative(model.status?.sync.lastRunAt)) · \(model.status?.sync.lastRunStatus ?? "–")")
            if let sync = model.status?.sync {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("History import").foregroundStyle(Theme.secondary)
                        Spacer()
                        Text(sync.backfillDone ? "Complete" : "\(Int(((sync.backfillProgress ?? 0) * 100).rounded()))%")
                    }
                    .font(.subheadline)
                    ProgressView(value: sync.backfillDone ? 1 : (sync.backfillProgress ?? 0)).tint(Theme.strain)
                    if let oldest = sync.backfillOldest {
                        Text("Imported back to \(Format.shortDay(oldest))").font(.caption).foregroundStyle(Theme.tertiary)
                    }
                }
            }
            Button {
                Task { await model.syncNow() }
            } label: {
                HStack {
                    Text(model.isSyncing ? "Syncing…" : "Sync now")
                    if model.isSyncing { Spacer(); ProgressView() }
                }
            }
            .disabled(model.isSyncing)
            Text("The server checks Google for new data every 5 minutes, even when this app is closed, and again whenever you open it or pull to refresh. Your band's data only reaches Google after the band syncs with the Google Health app on your phone.")
                .font(.caption)
                .foregroundStyle(Theme.tertiary)
        }
    }

    @ViewBuilder private var deviceSection: some View {
        if let devices = model.status?.devices, !devices.isEmpty {
            Section("Devices") {
                ForEach(devices) { d in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(d.name ?? "Fitbit device").font(.subheadline.weight(.semibold))
                        HStack(spacing: 12) {
                            if let level = d.batteryLevel {
                                Label("\(level)%", systemImage: batteryIcon(level))
                            } else if let status = d.batteryStatus {
                                Label(status, systemImage: "battery.50")
                            }
                            Text("Synced \(Format.relative(d.lastSyncTime))")
                        }
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                    }
                }
            }
        }
    }

    private func batteryIcon(_ level: Int) -> String {
        switch level {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }

    private var preferencesSection: some View {
        Section {
            Picker("Sex (for training load)", selection: $draft.sex) {
                Text("Not set").tag("unspecified")
                Text("Male").tag("male")
                Text("Female").tag("female")
            }
            Stepper("Sleep need: \(Format.duration(Double(draft.sleepNeedMin)))", value: $draft.sleepNeedMin, in: 300...720, step: 15)
            Stepper("Step goal: \(Format.number(Double(draft.stepGoal)))", value: $draft.stepGoal, in: 1000...50000, step: 500)
            Toggle("Set max heart rate manually", isOn: $useMaxHr)
            if useMaxHr {
                Stepper("Max HR: \(draft.maxHrOverride ?? 190) bpm",
                        value: Binding(get: { draft.maxHrOverride ?? 190 }, set: { draft.maxHrOverride = $0 }),
                        in: 120...230)
            }
            Picker("History to import", selection: $draft.backfillDays) {
                ForEach(historyOptions, id: \.self) { days in
                    Text(days >= 365 ? "\(days / 365) year\(days >= 730 ? "s" : "")" : "\(days) days").tag(days)
                }
            }
            Button {
                saving = true
                var toSave = draft
                if !useMaxHr { toSave.maxHrOverride = nil } else if toSave.maxHrOverride == nil { toSave.maxHrOverride = 190 }
                Task {
                    _ = await model.saveSettings(toSave)
                    saving = false
                }
            } label: {
                HStack {
                    Text("Save preferences")
                    if saving { Spacer(); ProgressView() }
                }
            }
            .disabled(saving || model.status == nil)
        } header: {
            Text("Preferences")
        } footer: {
            Text(maxHrText)
        }
    }

    /// The max heart rate in use and where it came from (status "maxHr"; older servers don't send it).
    private var maxHrText: String {
        let age = model.status?.profile.age.map { "age \($0)" } ?? "age unknown"
        guard let hr = model.status?.maxHr else {
            return "Without a manual value, max heart rate is the higher of 208 − 0.7 × age (\(age)) and the highest heart rate you have sustained in the last year."
        }
        let bpm = "\(Int(hr.value.rounded())) bpm"
        switch hr.source {
        case "override": return "Max heart rate in use: \(bpm), set by you."
        case "observed": return "Max heart rate in use: \(bpm), the highest heart rate you have sustained in the last year, which is above the 208 − 0.7 × age estimate (\(age))."
        default: return "Max heart rate in use: \(bpm), estimated as 208 − 0.7 × age (\(age)). It rises automatically if you sustain a higher heart rate."
        }
    }

    private var dataSection: some View {
        Section("Data") {
            NavigationLink("How the scores work") { ScoreInfoView() }
            Button("Prepare CSV export") { exportURL = model.csvExport() }
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Share \(exportURL.lastPathComponent)", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private var dangerSection: some View {
        Section {
            Button("Disconnect Google", role: .destructive) { confirmDisconnect = true }
            Button("Delete all synced data", role: .destructive) { confirmWipe = true }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            KeyValueRow(key: "App", value: appVersion)
            KeyValueRow(key: "Server", value: model.status?.version ?? "–")
            Text(model.baseURL.absoluteString).font(.caption2).foregroundStyle(Theme.tertiary)
        }
    }

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }
}

struct ScoreInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                info("Recovery (0–100%)", Theme.recoveryGreen, """
                Compares last night with your own previous 30 nights. HRV 45% (log RMSSD as a z-score, 50 + 25·z), \
                resting heart rate 25% (lower than usual scores higher), sleep score 20%, and vitals 10% \
                (skin temperature and breathing rate lose points when they are more than one standard deviation \
                from your baseline). It needs 5 nights of history and either HRV or resting heart rate.
                """)
                info("Strain (0–100)", Theme.strain, """
                Built from your minute-by-minute heart rate. Each minute above 30% of your heart-rate reserve adds \
                Banister TRIMP = HRR × a × e^(b × HRR) (a = 0.64, b = 1.92, or 0.86 / 1.67 if set to female). \
                Strain = 100 × (1 − e^(−TRIMP / 120)), so it climbs quickly at first and flattens near 100. \
                A single minute more than 30 bpm above both neighbours is a sensor glitch and is smoothed first. \
                The goal band comes from your recovery: 55–80 when green, 35–60 when yellow, 10–35 when red.
                """)
                info("Max heart rate", Theme.heart, """
                Heart-rate reserve runs from your resting heart rate to your max heart rate. Unless you set it \
                yourself, the max is the higher of 208 − 0.7 × age and the highest heart rate you have sustained \
                in the last year (a minute average with the minute next to it at most 15 bpm lower, so a \
                one-minute spike doesn't count). When it changes by 2 bpm or more, your history is recomputed.
                """)
                info("Sleep score (0–100)", Theme.sleep, """
                Duration 50% (time asleep ÷ your sleep need), efficiency 15% (time asleep ÷ the sleep period: \
                85% → 0, 98% → 100; Fitbit's sleep period starts when it detects you settling, so most nights \
                are 92–99%), deep + REM 20% (full marks at 15% deep and 20% REM), consistency 15% (bed and \
                wake time compared with your 14-night median; 2 hours off scores 0).
                """)
                info("Sleep details", Theme.sleep, """
                A day's sleep numbers come from one session: a night rather than a nap, then the one Google \
                marks as main sleep, then the longest. Every other session that day counts as a nap. \
                Awakenings are the times you were awake after first falling asleep and before the final \
                wake-up; "Awake after falling asleep" is their minutes. Time to fall asleep is the awake \
                stretch at the start of the night when Google reports none.
                """)
                info("Stress (0–100)", Theme.stress, """
                Google Health does not offer daytime HRV, so stress is estimated from heart rate. A minute counts \
                when you are awake, still (no steps in it or the 3 minutes before, and sedentary in Fitbit's \
                minute data when it has that) and not exercising or recovering from a workout (until your heart \
                rate is back near its level before the workout, 30–180 minutes after). Each minute scores 0 at \
                or below your usual still heart rate (the median of the last 30 days; until there are 7 days, \
                14% of heart-rate reserve above resting) and 100 at 15% of reserve above it. The day's stress \
                is the average: under 25 low, 25–49 moderate, 50–74 high, 75 or more very high.
                """)
                info("Tonight (sleep plan)", Theme.sleep, """
                Need tonight = your sleep need setting (Base), plus 0–45 minutes for the day's strain (nothing \
                at 35 or less, 45 minutes at 85 or more), plus a quarter of your last 7 nights' sleep debt (at \
                most an hour; naps on earlier days count as sleep), minus today's naps (at most an hour). \
                Time in bed = need ÷ your typical sleep efficiency \
                (median of 14 nights). Bedtime = your usual wake time for tomorrow's kind of day (weekday or \
                weekend, median of 28 nights) minus the time in bed.
                """)
                info("Journal effects", Theme.stress, """
                For each tag, the night and morning after tagged days (sleep score, time asleep, HRV, resting \
                heart rate, recovery) are compared with the night and morning after your other logged days. \
                "Nothing to note" counts as logged. A tag needs 3 logged days with it and 3 without. A \
                difference is "clear" when Welch's t is 2 or more, i.e. larger than your usual night-to-night \
                variation. It shows a pattern, not a cause.
                """)
                info("Partial and low-wear days", Theme.recoveryYellow, """
                Today's steps, calories and other day totals are still growing, so they are shown "so far" and \
                not compared with full days; Trends' 7D, 30D and longer ranges for day totals cover complete \
                days before today. Steps are compared with what you usually have by the same time. A finished \
                day is incomplete when the band recorded under 60% of your usual wear time (the median of your \
                worn days among the previous 30), or under 10 hours while you have fewer than 5 worn days. A \
                day without any minute heart rate (say, before you had the band) is incomplete once the band \
                has been worn. Incomplete days' totals stay visible but are left out of averages, records, \
                trends and correlations.
                """)
                info("Workouts", Theme.strain, """
                Peak minute HR is the highest one-minute average, after smoothing one-minute sensor spikes. \
                When Google's step count for a workout is missing or implies more than a metre per step, the \
                minute steps over the workout are shown instead (marked ≈). When under 70% of a workout has \
                heart rate, its strain and zones cover only those minutes and are marked partial.
                """)
                Text("These are FitStats' own transparent formulas. They are not Bevel's or Fitbit's scores (both are proprietary), and they are not medical advice.")
                    .font(.footnote)
                    .foregroundStyle(Theme.tertiary)
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("How scores work")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func info(_ title: String, _ color: Color, _ text: String) -> some View {
        Card {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(title).font(.headline)
            }
            Text(text).font(.footnote).foregroundStyle(Theme.secondary)
        }
    }
}
