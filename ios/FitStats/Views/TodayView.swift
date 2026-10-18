import SwiftUI

enum DetailRoute: Hashable {
    case recovery(String)
    case strain(String)
    case sleep(String)
    case stress(String)
    case metric(String)
    case workout(String, String) // date, exercise id
}

struct DetailDestination: View {
    let route: DetailRoute

    var body: some View {
        switch route {
        case .recovery(let d): RecoveryDetailView(date: d)
        case .strain(let d): StrainDetailView(date: d)
        case .sleep(let d): SleepDetailView(date: d)
        case .stress(let d): StressDetailView(date: d)
        case .metric(let key):
            if let def = MetricCatalog.def(key) {
                MetricDetailView(def: def)
            } else {
                EmptyStateView(icon: "questionmark", title: "Unknown metric", message: key)
            }
        case .workout(let date, let id): WorkoutDetailView(date: date, exerciseId: id)
        }
    }
}

struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var coach: CoachStore
    @State private var selected: String?
    /// The cards on Home, in order (Views/Home/HomeLayout.swift).
    @AppStorage(HomeLayout.storageKey) private var storedCards = ""
    /// Every card while CI takes screenshots (FITSTATS_HOME_CARDS=all); edits then stay in memory.
    @State private var fixtureCards: [HomeCard]? = HomeLayout.fixtureCards
    @State private var editingHome = false
    @State private var editHaptic = 0

    private var date: String { selected ?? model.today }
    private var day: DayRecord? { model.daysByDate[date] }
    private var detail: DayDetail? { model.dayDetails[date] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    WeekStrip(today: model.today, selected: $selected) { model.daysByDate[$0]?.double("recovery") }
                    banners
                    if day == nil {
                        Card {
                            EmptyStateView(
                                icon: "clock.arrow.circlepath",
                                title: "No data for this day",
                                message: model.days.isEmpty
                                    ? "Your history is still syncing. Pull down to refresh in a minute."
                                    : "Nothing was recorded on \(Format.longDay(date))."
                            )
                        }
                    } else if visibleCards.isEmpty {
                        Card {
                            EmptyStateView(
                                icon: "square.grid.2x2",
                                title: "Nothing on Home for this day",
                                message: "Your Home cards only show on today. Tap Edit Home screen to add cards for past days."
                            )
                        }
                    }
                    ForEach(visibleCards) { card in
                        homeCard(card, day: day)
                    }
                    editHomeButton
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
                .sensoryFeedback(.impact(weight: .medium), trigger: editHaptic)
            }
            .refreshable {
                await model.pullToRefresh()
                await model.loadDay(date, force: true)
            }
            .screenBackground()
            .task(id: date) { await model.loadDay(date) }
            .navigationDestination(for: DetailRoute.self) { DetailDestination(route: $0) }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { header }
            .sheet(isPresented: $editingHome) {
                HomeEditorView(cards: homeLayout)
                    .environmentObject(model)
                    .environmentObject(coach)
            }
        }
    }

    // MARK: home cards

    private var homeCards: [HomeCard] {
        fixtureCards ?? HomeLayout.decode(storedCards)
    }

    /// The Home cards Today draws for this day, so a skipped card never leaves an empty
    /// container (with its gesture) behind.
    private var visibleCards: [HomeCard] {
        homeCards.filter { card in isVisible(card) }
    }

    /// Cards built from this day's record. The other cards take only the date and handle a
    /// missing day themselves.
    private static let dayRecordCards: Set<HomeCard> = [.scores, .tonight, .journal, .vitals, .activity, .heartRate, .workouts]

    /// Today-only cards are skipped on past days. A day without a record skips the cards that
    /// need it, and while the history is still syncing (no days at all) only the empty state
    /// shows.
    private func isVisible(_ card: HomeCard) -> Bool {
        if card.todayOnly && date != model.today { return false }
        if day == nil {
            if model.days.isEmpty { return false }
            if Self.dayRecordCards.contains(card) { return false }
        }
        return true
    }

    private var homeLayout: Binding<[HomeCard]> {
        Binding(
            get: { fixtureCards ?? HomeLayout.decode(storedCards) },
            set: { cards in
                if fixtureCards != nil {
                    fixtureCards = cards
                } else {
                    storedCards = HomeLayout.encode(cards)
                }
            }
        )
    }

    /// One card in its container: holding it for a moment opens the Home editor. The long
    /// press is high priority so it wins over the links inside, but it fails as soon as the
    /// finger lifts or moves, so taps still reach those links and the page still scrolls.
    private func homeCard(_ card: HomeCard, day: DayRecord?) -> some View {
        homeCardContent(card, day: day)
            .highPriorityGesture(
                LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                    editHaptic += 1
                    editingHome = true
                }
            )
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: Text("Edit Home screen")) { editingHome = true }
            .accessibilityIdentifier("home-card-\(card.rawValue)")
    }

    /// `visibleCards` already skips today-only cards on past days and the day-record cards
    /// when there is no record; the checks here only keep each case safe on its own.
    @ViewBuilder private func homeCardContent(_ card: HomeCard, day: DayRecord?) -> some View {
        switch card {
        case .scores:
            if let day { scoresCard(day) }
        case .tonight:
            if day != nil && date == model.today { SleepPlanCard(plan: model.sleepPlan) }
        case .journal:
            if day != nil { JournalCard(date: date) }
        case .vitals:
            if let day { vitalsCard(day) }
        case .activity:
            if let day { activityCard(day) }
        case .heartRate:
            if let day { heartCard(day) }
        case .workouts:
            if day != nil { workoutsCard }
        case .lastNight:
            LastNightCard(date: date)
        case .recoveryTrend:
            RecoveryTrendCard(date: date)
        case .hrvTrend:
            HRVTrendCard(date: date)
        case .restingHrTrend:
            RestingHRTrendCard(date: date)
        case .stressDay:
            StressDayCard(date: date)
        case .thisWeek:
            ThisWeekCard(date: date)
        case .weeklyZoneMinutes:
            WeeklyZoneMinutesCard(date: date)
        case .streaks:
            StreaksCard(date: date)
        case .topInsight:
            TopInsightCard(date: date)
        case .coachBrief:
            if date == model.today { CoachBriefCard(date: date) }
        case .body:
            BodyCard(date: date)
        }
    }

    private var editHomeButton: some View {
        Button {
            editingHome = true
        } label: {
            Label("Edit Home screen", systemImage: "slider.horizontal.3")
                .font(.caption.weight(.semibold))
        }
        .accessibilityIdentifier("home-edit")
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: header & banners

    /// Lives in the navigation bar, so scrolled content passes under a blurred bar instead of the status bar.
    @ToolbarContentBuilder private var header: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { shift(-1) } label: {
                Image(systemName: "chevron.left").foregroundStyle(.white)
            }
            .accessibilityLabel("Previous day")
        }
        ToolbarItem(placement: .principal) {
            VStack(spacing: 0) {
                Text(Format.prettyDay(date, today: model.today)).font(.headline)
                Text(Format.longDay(date)).font(.caption2).foregroundStyle(Theme.secondary)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { shift(1) } label: {
                Image(systemName: "chevron.right").foregroundStyle(.white)
            }
            .disabled(date >= model.today)
            .opacity(date >= model.today ? 0.3 : 1)
            .accessibilityLabel("Next day")
        }
    }

    private func shift(_ n: Int) {
        let next = Format.addDays(date, n)
        selected = next >= model.today ? nil : next
    }

    @ViewBuilder private var banners: some View {
        if model.needsReconnect {
            Banner(icon: "exclamationmark.triangle.fill",
                   text: "Google access has expired, so new data is not syncing.",
                   color: Theme.recoveryRed, actionTitle: "Reconnect") {
                Task { await model.connect() }
            }
        }
        if let sync = model.status?.sync, !sync.backfillDone, let p = sync.backfillProgress {
            Banner(icon: "arrow.triangle.2.circlepath",
                   text: "Importing your history… \(Int((p * 100).rounded()))% (the server keeps going in the background)",
                   color: Theme.strain)
        }
        if let notice = model.noticeMessage {
            Banner(icon: "info.circle.fill", text: notice, color: Theme.stress, actionTitle: "OK") {
                model.noticeMessage = nil
            }
        }
        if let error = model.errorMessage {
            Banner(icon: "wifi.exclamationmark", text: error, color: Theme.recoveryYellow, actionTitle: "Dismiss") {
                model.errorMessage = nil
            }
        }
    }

    // MARK: scores

    private func strainTarget(_ day: DayRecord) -> ClosedRange<Double>? {
        guard let arr = day.json("score_details")?["strainTarget"]?.array, arr.count == 2,
              let lo = arr[0].double, let hi = arr[1].double, lo <= hi else { return nil }
        return lo...hi
    }

    private func scoresCard(_ day: DayRecord) -> some View {
        let recovery = day.double("recovery")
        let breakdown = ScoreBreakdown(day.json("score_details")?["recovery"])
        let caption = recovery != nil
            ? Theme.recoveryLabel(recovery)
            : (breakdown.status == "calibrating" ? "Calibrating" : "No data")
        return Card {
            NavigationLink(value: DetailRoute.recovery(date)) {
                HStack(spacing: 18) {
                    ScoreRing(title: "Recovery", value: recovery, maxValue: 100,
                              color: Theme.recoveryColor(recovery), caption: caption,
                              size: 128, lineWidth: 14, suffix: "%")
                    recoverySummary(day)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ring-recovery")
            Divider().overlay(Theme.track)
            HStack(alignment: .top) {
                smallRing(.strain(date), "Strain", day.double("strain"), Theme.strain, Theme.strainEnd,
                          strainTarget(day).map { "Goal \(Int($0.lowerBound))–\(Int($0.upperBound))" },
                          target: strainTarget(day))
                Spacer(minLength: 4)
                smallRing(.sleep(date), "Sleep", day.double("sleep_score"), Theme.sleep, nil,
                          Format.duration(day.double("sleep_asleep_min")))
                Spacer(minLength: 4)
                smallRing(.stress(date), "Stress", day.double("stress"), Theme.stressColor(day.double("stress")), nil,
                          Theme.stressLabel(day.double("stress")))
            }
        }
    }

    private func smallRing(_ route: DetailRoute, _ title: String, _ value: Double?, _ color: Color, _ end: Color?,
                           _ caption: String?, target: ClosedRange<Double>? = nil) -> some View {
        NavigationLink(value: route) {
            ScoreRing(title: title, value: value, maxValue: 100, color: color, endColor: end,
                      caption: caption, size: 88, lineWidth: 9, target: target)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ring-\(title.lowercased())")
    }

    private func recoverySummary(_ day: DayRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            summaryRow("HRV", key: "hrv_rmssd", day)
            summaryRow("Resting HR", key: "rhr", day)
            summaryRow("Sleep", key: "sleep_asleep_min", day)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryRow(_ title: String, key: String, _ day: DayRecord) -> some View {
        let def = MetricCatalog.def(key)!
        let value = def.value(day)
        let base = model.baseline(def, before: date)
        var change: Double? = nil
        if let value, let base, base != 0 { change = (value - base) / abs(base) * 100 }
        return VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Theme.secondary)
            HStack(spacing: 6) {
                Text(def.formatted(value)).font(Theme.number(17, weight: .semibold))
                DeltaBadge(change: change, better: def.better)
            }
        }
    }

    // MARK: vitals & activity

    /// Day totals are only compared when the day is complete: today's are "so far" and a
    /// low-wear day's are incomplete. Everything else is compared with the 30-day average.
    private func tile(_ key: String, _ day: DayRecord) -> some View {
        let def = MetricCatalog.def(key)!
        let value = def.value(day)
        let base = model.baseline(def, before: date)
        let soFar = def.isDayTotal && date >= model.today
        var change: Double? = nil
        if model.countsToward(def, day), def.format != .clock, key != "skin_temp_dev", let value, let base, base != 0 {
            change = (value - base) / abs(base) * 100
        }
        return NavigationLink(value: DetailRoute.metric(key)) {
            MetricTile(title: def.shortLabel, value: def.formatted(value),
                       sub: soFar ? "so far" : base.map { "30d avg \(def.formatted($0, withUnit: false))" },
                       icon: def.icon, color: def.category.color, change: change, better: def.better)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func vitalsCard(_ day: DayRecord) -> some View {
        let keys = ["rhr", "hrv_rmssd", "spo2_avg", "resp_rate", "skin_temp_dev", "vo2max"].filter(model.recorded.contains)
        if !keys.isEmpty {
            Card {
                SectionHeader(title: "Vitals", subtitle: "Measured overnight, compared with your 30-day average")
                TwoColumnTiles(items: keys) { key in
                    tile(key, day)
                }
            }
        }
    }

    private func activityCard(_ day: DayRecord) -> some View {
        let steps = day.double("steps")
        let goal = Double(model.status?.settings.stepGoal ?? 10000)
        let keys = ["calories_total", "calories_active", "azm_total", "distance_km", "floors", "active_min_total"].filter(model.recorded.contains)
        return Card {
            SectionHeader(title: "Activity")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Format.number(steps)).font(Theme.number(34))
                Text("steps").foregroundStyle(Theme.secondary)
                Spacer()
                Text("Goal \(Format.number(goal))").font(.caption).foregroundStyle(Theme.tertiary)
            }
            ProgressView(value: min(1, (steps ?? 0) / max(goal, 1)))
                .tint(Theme.strain)
            stepsComparison(day)
            if !keys.isEmpty {
                TwoColumnTiles(items: keys) { key in
                    tile(key, day)
                }
            }
            if day.bool("low_wear") == true, let wear = day.double("wear_min") {
                Label(lowWearText(wear), systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.recoveryYellow)
            }
        }
    }

    private func lowWearText(_ wear: Double) -> String {
        let usual = model.usualWear(before: date).map { " (usually \(Format.duration($0)))" } ?? ""
        return "Band worn \(Format.duration(wear)) this day\(usual), so its totals are left out of your averages."
    }

    /// Today: steps against what you usually have by the time the data reaches. Other days:
    /// against the 30-day average. Never for an incomplete (low-wear) day.
    @ViewBuilder private func stepsComparison(_ day: DayRecord) -> some View {
        if let steps = day.double("steps"), day.bool("low_wear") != true {
            if date == model.today {
                let minute = model.lastDataMinute(date) ?? model.localMinuteNow
                if let typical = model.typicalSteps(before: date, atMinute: minute) {
                    comparison("Usually \(Format.number(typical)) by \(Format.clock(Double(minute)))", steps, typical)
                }
            } else if let base = model.baseline(MetricCatalog.def("steps")!, before: date) {
                comparison("30-day average \(Format.number(base))", steps, base)
            }
        }
    }

    private func comparison(_ text: String, _ value: Double, _ base: Double) -> some View {
        HStack(spacing: 6) {
            Text(text).font(.caption).foregroundStyle(Theme.tertiary)
            Spacer()
            DeltaBadge(change: base > 0 ? (value - base) / base * 100 : nil, better: .higher)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: heart & workouts

    private func heartCard(_ day: DayRecord) -> some View {
        Card {
            HStack {
                SectionHeader(title: "Heart rate")
                Spacer()
                Text("\(Format.number(day.double("hr_min"))) – \(Format.number(day.double("hr_max"))) bpm")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
            }
            if let hr = detail?.intraday?.hr, hr.contains(where: { $0 != nil }) {
                HeartRateDayChart(hr: hr, rhr: day.double("rhr"))
            } else if detail == nil && model.failedDays.contains(date) {
                Button {
                    Task { await model.loadDay(date, force: true) }
                } label: {
                    Label("Couldn't load the minute data. Tap to try again.", systemImage: "arrow.clockwise")
                        .font(.footnote)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else if detail == nil {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Text("No minute-level heart rate for this day.")
                    .font(.footnote)
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }

    @ViewBuilder private var workoutsCard: some View {
        if let exercises = detail?.exercises, !exercises.isEmpty {
            Card {
                SectionHeader(title: "Workouts")
                ForEach(exercises) { x in
                    NavigationLink(value: DetailRoute.workout(date, x.id)) {
                        WorkoutRow(exercise: x, zone: model.zone)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("workout-row")
                }
            }
        }
    }

    /// When the server last fetched from Google, and when the band last synced with the
    /// phone (the step FitStats cannot speed up).
    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if model.isSyncing {
                    ProgressView().scaleEffect(0.8)
                    Text("Getting the latest from Google…").font(.caption).foregroundStyle(Theme.secondary)
                } else {
                    Text(updatedText).font(.caption).foregroundStyle(Theme.tertiary)
                }
                Spacer()
                Button {
                    Task { await model.syncNow() }
                } label: {
                    Label("Sync now", systemImage: "arrow.clockwise").font(.caption.weight(.semibold))
                }
                .disabled(model.isSyncing)
            }
            if let band = model.band, let synced = Format.timestamp(band.lastSyncTime) {
                let name = band.name ?? "Your band"
                if Date().timeIntervalSince(synced) > 30 * 60 {
                    Label("\(name) last synced to your phone \(Format.relative(band.lastSyncTime)). Open the Google Health app to send newer data.",
                          systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(Theme.recoveryYellow)
                } else {
                    Text("\(name) synced to your phone \(Format.relative(band.lastSyncTime))")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiary)
                }
            }
        }
        .padding(.top, 4)
    }

    private var updatedText: String {
        guard let fetched = model.status?.sync.lastRecentSyncAt else { return "Not updated yet" }
        return "Updated \(Format.relative(fetched))"
    }
}

/// Last seven days with a small recovery ring each; tapping one selects it.
struct WeekStrip: View {
    let today: String
    @Binding var selected: String?
    let recoveryFor: (String) -> Double?

    var body: some View {
        let current = selected ?? today
        HStack(spacing: 4) {
            ForEach((0..<7).reversed(), id: \.self) { offset in
                let date = Format.addDays(today, -offset)
                let recovery = recoveryFor(date)
                Button {
                    selected = date == today ? nil : date
                } label: {
                    VStack(spacing: 5) {
                        Text(Format.weekdayLetter(date))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.tertiary)
                        ZStack {
                            Circle().stroke(Theme.track, lineWidth: 3)
                            Circle()
                                .trim(from: 0, to: min(1, (recovery ?? 0) / 100))
                                .stroke(Theme.recoveryColor(recovery), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text(Format.dayNumber(date)).font(.caption.weight(.semibold))
                        }
                        .frame(width: 32, height: 32)
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(date == current ? Color.white.opacity(0.09) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("day-\(date)")
            }
        }
    }
}

struct WorkoutRow: View {
    let exercise: Exercise
    var zone: TimeZone?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: exercise.symbol)
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.strain.opacity(0.18)))
                .foregroundStyle(Theme.strain)
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(Theme.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(exercise.durationText)
                    .font(Theme.number(15, weight: .semibold))
                if let strain = exercise.strain {
                    Text("strain \(Format.number(strain, decimals: 1))").font(.caption2).foregroundStyle(Theme.tertiary)
                } else if let hr = exercise.avgHr {
                    Text("\(Int(hr)) bpm avg").font(.caption2).foregroundStyle(Theme.tertiary)
                }
            }
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var parts: [String] = []
        if let start = Format.timestamp(exercise.startTime) { parts.append(Format.time(start, zone: zone)) }
        if let kcal = exercise.calories { parts.append("\(Int(kcal)) kcal") }
        if let m = exercise.distanceM, m > 0 { parts.append(String(format: "%.2f km", m / 1000)) }
        if let azm = exercise.azm, azm > 0 { parts.append("\(Int(azm)) AZM") }
        // Only an unusual origin is named here; a workout started on a device is the norm.
        if exercise.recordingMethod != "ACTIVELY_MEASURED", let origin = exercise.originLabel { parts.append(origin) }
        return parts.joined(separator: " · ")
    }
}
