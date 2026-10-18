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
                Text("Removes every synced day, sleep, workout and the Google connection from your Supabase database. This cannot be undone.")
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
            KeyValueRow(key: "Last sync", value: Format.relative(model.status?.sync.lastRunAt))
            KeyValueRow(key: "Last result", value: model.status?.sync.lastRunStatus ?? "–")
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
            Text("The server syncs automatically every 15 minutes, even when this app is closed.")
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
            Text("Without a manual value, max heart rate is estimated as 208 − 0.7 × age (age \(model.status?.profile.age.map { "\($0)" } ?? "unknown")).")
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
                The goal band comes from your recovery: 55–80 when green, 35–60 when yellow, 10–35 when red.
                """)
                info("Sleep score (0–100)", Theme.sleep, """
                Duration 50% (time asleep ÷ your sleep need), efficiency 15% (70% → 0, 95% → 100), \
                deep + REM 20% (full marks at 15% deep and 20% REM), consistency 15% (bed and wake time \
                compared with your 14-night median; 2 hours off scores 0).
                """)
                info("Stress (0–100)", Theme.stress, """
                Google Health does not offer daytime HRV, so stress is estimated from heart rate: for every minute \
                you are awake, still (no steps in the last 3 minutes) and not exercising, heart rate 5% of reserve \
                above resting scores 0 and 30% or more scores 100. The day's stress is the average.
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
