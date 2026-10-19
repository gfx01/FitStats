import Combine
import SwiftUI
import UniformTypeIdentifiers

enum DetailRoute: Hashable {
    case recovery(String)
    case strain(String)
    case sleep(String)
    case stress(String)
    case metric(String)
    case workout(String, String) // date, exercise id
    case liveHeartRate
    /// A Home card at full size, opened from its small or medium version.
    case homeCard(HomeCardSpec, String) // card with its settings, date
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
        case .liveHeartRate: LiveHeartRateView()
        case .homeCard(let spec, let d): HomeCardDetailView(spec: spec, date: d)
        }
    }
}

struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var coach: CoachStore
    @EnvironmentObject private var live: LiveHeartRateMonitor
    @State private var selected: String?
    /// Home: the cards, their sizes and settings, and the time-of-day layouts (HomeConfig).
    @AppStorage(HomeLayout.configKey) private var storedConfig = ""
    /// Every card while CI takes screenshots (FITSTATS_HOME_CARDS=all); edits then stay in memory.
    @State private var fixtureConfig: HomeConfig? = HomeLayout.fixtureItems.map { HomeConfig(items: $0) }
    /// The time-of-day layout being edited (edit mode only).
    @State private var editingPage: HomePage = .day
    @State private var editingTimes = false
    /// Moves Home to the next time-of-day layout while it's open.
    @State private var now = Date()
    @Environment(\.scenePhase) private var scenePhase
    /// Edit mode, like the iOS Home Screen: the cards wobble and can be moved, resized, removed
    /// and added in place.
    @State private var editing = false
    /// The card being dragged while editing (its id).
    @State private var dragging: String?
    /// Where it hovers, and the card it would stack with if dropped now.
    @State private var hover: HomeHover?
    @State private var stackTarget: String?
    /// The card whose resize outline is up, drawn above the others.
    @State private var resizingID: String?
    /// The card whose settings sheet is open.
    @State private var settingsItem: HomeItem?
    @State private var editHaptic = 0

    private static let addSectionID = "home-add-section"
    private static let minuteTicker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var date: String { selected ?? model.today }
    private var day: DayRecord? { model.daysByDate[date] }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        if editing {
                            editHeader
                        } else {
                            WeekStrip(today: model.today, selected: $selected) { model.daysByDate[$0]?.double("recovery") }
                            banners
                            emptyState
                        }
                        HomeGridLayout(columnSpacing: 12, rowSpacing: 14) {
                            ForEach(gridItems) { item in
                                cell(item)
                                    .zIndex(resizingID == item.id ? 1 : 0)
                                    .layoutValue(key: HomeCardSizeKey.self, value: item.size)
                            }
                        }
                        .onDrop(of: [UTType.text], delegate: HomeDropEndDelegate(dragging: $dragging, hover: $hover, stackTarget: $stackTarget))
                        if editing {
                            HomeAddSection(date: date, shown: items, isDefault: items == HomeLayout.defaultItems,
                                           canShow: isVisible, onAdd: add, onReset: reset)
                                .id(Self.addSectionID)
                        } else {
                            editHomeButton
                            footer
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, editing ? 8 : 0)
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
                .toolbar { header(proxy) }
                .sheet(item: $settingsItem) { item in
                    HomeCardSettingsView(draft: item, canRemove: items.count > 1,
                                         onChange: update, onRemove: { remove(item.id) },
                                         onExtract: { entry in extract(entry, from: item.id) })
                        .environmentObject(model)
                }
                .sheet(isPresented: $editingTimes) {
                    HomeTimesSheet(config: configBinding)
                }
                .onReceive(Self.minuteTicker) { now = $0 }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { now = Date() }
                }
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
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
        } else if visibleItems.isEmpty {
            Card {
                EmptyStateView(
                    icon: "square.grid.2x2",
                    title: "Nothing on Home for this day",
                    message: "Your Home cards only show on today. Tap Edit Home screen to add cards for past days."
                )
            }
        }
    }

    /// The hint, and with time-of-day layouts on, which one is being edited.
    private var editHeader: some View {
        VStack(spacing: 10) {
            Text("Tap a card for its settings. Hold and drag to move it, or drop it on another card's middle to stack them. Drag the corner handle to resize.")
                .font(.caption)
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Card(padding: 12) {
                Toggle(isOn: timeOfDayBinding) {
                    Label("Change Home by time of day", systemImage: "clock.arrow.2.circlepath")
                        .font(.subheadline.weight(.semibold))
                }
                .tint(Theme.recoveryGreen)
                .accessibilityIdentifier("home-time-of-day")
                if config.timeOfDay {
                    Picker("Layout", selection: $editingPage) {
                        ForEach(HomePage.allCases) { page in
                            Text(page.title).tag(page)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("home-page-picker")
                    Button {
                        editingTimes = true
                    } label: {
                        HStack {
                            Text(timesText)
                                .font(.caption)
                                .foregroundStyle(Theme.secondary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Text("Change").font(.caption.weight(.semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.recoveryGreen)
                }
            }
        }
        .padding(.bottom, 4)
    }

    private var timesText: String {
        let c = config
        return "Morning from \(Format.clock(Double(c.morningStart))), day from \(Format.clock(Double(c.dayStart))), evening from \(Format.clock(Double(c.eveningStart)))."
    }

    // MARK: home cards

    private var config: HomeConfig {
        fixtureConfig ?? HomeLayout.config(from: storedConfig)
    }

    /// Saves Home, stamped with the time of the edit (the newer copy wins on the server).
    private func save(_ config: HomeConfig) {
        var stamped = config
        stamped.editedAt = Date().timeIntervalSince1970
        if fixtureConfig != nil {
            fixtureConfig = stamped
        } else {
            storedConfig = HomeLayout.encode(stamped)
            model.homeLayoutEdited()
        }
    }

    private var configBinding: Binding<HomeConfig> {
        Binding(get: { config }, set: { save($0) })
    }

    /// The time-of-day layout on screen: the one being edited, else the one for now; nil when
    /// Home has a single layout.
    private var page: HomePage? {
        guard config.timeOfDay else { return nil }
        return editing ? editingPage : config.page(at: now)
    }

    private var items: [HomeItem] {
        config.items(for: page)
    }

    private var layout: Binding<[HomeItem]> {
        Binding(
            get: { config.items(for: page) },
            set: { next in
                var c = config
                c.setItems(next, for: page)
                save(c)
            }
        )
    }

    /// Turning it on gives each part of the day a copy of the current layout to start from;
    /// turning it off keeps them for next time.
    private var timeOfDayBinding: Binding<Bool> {
        Binding(
            get: { config.timeOfDay },
            set: { on in
                var c = config
                if on {
                    if c.morning == nil { c.morning = c.items }
                    if c.day == nil { c.day = c.items }
                    if c.evening == nil { c.evening = c.items }
                    editingPage = c.page(at: Date())
                }
                c.timeOfDay = on
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { save(c) }
            }
        )
    }

    /// The cards Today draws for this day, so a skipped card never leaves an empty cell behind.
    private var visibleItems: [HomeItem] {
        items.filter(isVisible)
    }

    /// A Smart Stack shows when any of its cards can.
    private func isVisible(_ item: HomeItem) -> Bool {
        if item.card == .stack { return !visibleEntries(item).isEmpty }
        return isVisible(item.card)
    }

    private func visibleEntries(_ item: HomeItem) -> [StackEntry] {
        (item.options.stack ?? []).filter { $0.card != .stack && isVisible($0.card) }
    }

    /// While editing every card shows (the hidden ones as placeholders), so each can be
    /// arranged.
    private var gridItems: [HomeItem] {
        editing ? items : visibleItems
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

    private func hiddenReason(_ card: HomeCard) -> String {
        if card == .stack { return "None of its cards has anything to show on this day." }
        if card.todayOnly && date != model.today { return "Shows on today only." }
        return model.days.isEmpty ? "Shows once your history has synced." : "Shows once today's data has synced."
    }

    /// One cell of the grid. Holding a card for a moment starts editing: the long press is high
    /// priority so it wins over the links inside, but it fails as soon as the finger lifts or
    /// moves, so taps still reach those links and the page still scrolls.
    @ViewBuilder private func cell(_ item: HomeItem) -> some View {
        if editing {
            HomeEditCell(
                item: item,
                seed: item.id.unicodeScalars.reduce(0) { $0 + Int($1.value) },
                canRemove: items.count > 1,
                isDragged: dragging == item.id,
                isStackTarget: stackTarget == item.id,
                onRemove: { remove(item.id) },
                onResize: { resize(item.id, to: $0) },
                onMove: { move(item.id, by: $0) },
                onEdit: { settingsItem = item },
                onResizing: { on in resizingID = on ? item.id : nil },
                onDragStart: {
                    dragging = item.id
                    hover = nil
                    stackTarget = nil
                    return NSItemProvider(object: item.id as NSString)
                },
                makeDrop: { size in
                    HomeDropDelegate(target: item.id, size: size, items: layout, dragging: $dragging,
                                     hover: $hover, stackTarget: $stackTarget, onStack: stack)
                }
            ) { size in
                cellContent(item, size: size)
            }
            .accessibilityIdentifier("home-card-\(item.id)")
        } else {
            cellContent(item, size: item.size)
                .highPriorityGesture(
                    LongPressGesture(minimumDuration: 0.45).onEnded { _ in startEditing() }
                )
                .accessibilityElement(children: .contain)
                .accessibilityAction(named: Text("Edit Home screen")) { startEditing() }
                .accessibilityIdentifier("home-card-\(item.id)")
        }
    }

    /// The card at `size`: its own, or the size a resize outline previews.
    @ViewBuilder private func cellContent(_ item: HomeItem, size: CardSize) -> some View {
        if !isVisible(item) {
            HomeCardPlaceholder(card: item.card, title: item.title, size: size, reason: hiddenReason(item.card))
        } else if item.card == .stack {
            SmartStackView(entries: visibleEntries(item), size: size, date: date, rotate: item.options.rotate ?? true)
        } else if size == .large {
            HomeLargeCard(spec: item.spec, date: date)
        } else {
            HomeGlance(spec: item.spec, size: size, date: date)
        }
    }

    private func startEditing() {
        editHaptic += 1
        dragging = nil
        editingPage = config.page(at: now)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            selected = nil
            editing = true
        }
    }

    private func finishEditing() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            editing = false
            dragging = nil
            hover = nil
            stackTarget = nil
        }
    }

    /// A card dropped on another's middle: the two become a Smart Stack where the target was
    /// (each keeps its settings), or the card joins the target stack.
    private func stack(_ draggedID: String, onto targetID: String) {
        var next = items
        guard let di = next.firstIndex(where: { $0.id == draggedID }),
              let ti = next.firstIndex(where: { $0.id == targetID }) else { return }
        let dragged = next[di]
        let target = next[ti]
        guard dragged.card != .stack else { return }
        let entry = StackEntry(id: dragged.id, card: dragged.card, options: dragged.options)
        if target.card == .stack {
            next[ti].options.stack = (target.options.stack ?? []) + [entry]
        } else {
            let first = StackEntry(id: target.id, card: target.card, options: target.options)
            next[ti] = HomeLayout.newItem(.stack, size: target.size == .small ? .small : .medium,
                                          options: CardOptions(stack: [first, entry], rotate: false))
        }
        next.remove(at: di)
        editHaptic += 1
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { layout.wrappedValue = next }
    }

    /// "Move to Home" in a stack's settings: the card goes back on Home right after the stack.
    /// A one-of-a-kind card already on Home just leaves the stack.
    private func extract(_ entry: StackEntry, from stackID: String) {
        var next = items
        guard let si = next.firstIndex(where: { $0.id == stackID }) else { return }
        let size = next[si].size
        var card = HomeLayout.newItem(entry.card, size: entry.card.sizes.contains(size) ? size : entry.card.defaultSize,
                                      options: entry.options)
        if !entry.card.isUnique { card.id = entry.id }
        guard !next.contains(where: { $0.id == card.id || (entry.card.isUnique && $0.card == entry.card) }) else { return }
        next.insert(card, at: si + 1)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { layout.wrappedValue = next }
    }

    private func remove(_ id: String) {
        guard items.count > 1 else { return }
        let next = items.filter { $0.id != id }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { layout.wrappedValue = next }
    }

    private func resize(_ id: String, to size: CardSize) {
        var next = items
        guard let i = next.firstIndex(where: { $0.id == id }), next[i].size != size, next[i].card.sizes.contains(size) else { return }
        next[i].size = size
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { layout.wrappedValue = next }
    }

    /// A change from the card's settings sheet.
    private func update(_ item: HomeItem) {
        var next = items
        guard let i = next.firstIndex(where: { $0.id == item.id }), next[i] != item else { return }
        next[i] = item
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { layout.wrappedValue = next }
    }

    /// VoiceOver's move up / move down.
    private func move(_ id: String, by offset: Int) {
        var next = items
        guard let i = next.firstIndex(where: { $0.id == id }) else { return }
        let j = min(max(0, i + offset), next.count - 1)
        guard i != j else { return }
        next.swapAt(i, j)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { layout.wrappedValue = next }
    }

    private func add(_ item: HomeItem) {
        guard !items.contains(where: { $0.id == item.id || (item.card.isUnique && $0.card == item.card) }) else { return }
        editHaptic += 1
        let next = items + [item]
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { layout.wrappedValue = next }
    }

    private func reset() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { layout.wrappedValue = HomeLayout.defaultItems }
    }

    private var editHomeButton: some View {
        Button {
            startEditing()
        } label: {
            Label("Edit Home screen", systemImage: "slider.horizontal.3")
                .font(.caption.weight(.semibold))
        }
        .accessibilityIdentifier("home-edit")
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: header & banners

    /// Lives in the navigation bar, so scrolled content passes under a blurred bar instead of the
    /// status bar. While editing it holds Add and Done instead of the day controls.
    @ToolbarContentBuilder private func header(_ proxy: ScrollViewProxy) -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if editing {
                Button {
                    withAnimation { proxy.scrollTo(Self.addSectionID, anchor: .top) }
                } label: {
                    Image(systemName: "plus").font(.body.weight(.semibold))
                }
                .accessibilityLabel("Add a card")
                .accessibilityIdentifier("home-add-cards")
            } else {
                Button { shift(-1) } label: {
                    Image(systemName: "chevron.left").foregroundStyle(.white)
                }
                .accessibilityLabel("Previous day")
            }
        }
        ToolbarItem(placement: .principal) {
            if editing {
                Text("Edit Home").font(.headline)
            } else {
                VStack(spacing: 0) {
                    Text(Format.prettyDay(date, today: model.today)).font(.headline)
                    Text(Format.longDay(date)).font(.caption2).foregroundStyle(Theme.secondary)
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if !editing && live.enabled {
                NavigationLink(value: DetailRoute.liveHeartRate) {
                    Image(systemName: "heart.text.square").foregroundStyle(Theme.heart)
                }
                .accessibilityLabel("Live heart rate")
                .accessibilityIdentifier("open-live-hr")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if editing {
                Button("Done") { finishEditing() }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("home-done")
            } else {
                Button { shift(1) } label: {
                    Image(systemName: "chevron.right").foregroundStyle(.white)
                }
                .disabled(date >= model.today)
                .opacity(date >= model.today ? 0.3 : 1)
                .accessibilityLabel("Next day")
            }
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

    /// When the server last fetched from Google, and when the band last synced with the
    /// phone (the step FitStats cannot speed up).
    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let page {
                Label("\(page.title) Home · changes by time of day", systemImage: page.icon)
                    .font(.caption)
                    .foregroundStyle(Theme.tertiary)
            }
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

/// A Home card at full size: everything the card has. Today shows it for large cards, and its
/// own screen (HomeCardDetailView) opens it from a small or medium one.
struct HomeLargeCard: View {
    let spec: HomeCardSpec
    let date: String
    @EnvironmentObject private var model: AppModel

    private var card: HomeCard { spec.card }

    private var day: DayRecord? { model.daysByDate[date] }
    private var detail: DayDetail? { model.dayDetails[date] }

    var body: some View {
        content(day: day)
    }

    /// Today already skips today-only cards on past days and the day-record cards when there is
    /// no record; the checks here only keep each case safe on its own.
    @ViewBuilder private func content(day: DayRecord?) -> some View {
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
            RecoveryTrendCard(date: date, days: spec.days)
        case .hrvTrend:
            HRVTrendCard(date: date, windowDays: spec.days)
        case .restingHrTrend:
            RestingHRTrendCard(date: date, windowDays: spec.days)
        case .stressDay:
            StressDayCard(date: date)
        case .thisWeek:
            ThisWeekCard(date: date, keys: spec.options.metrics)
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
        case .trainingLoad:
            TrainingLoadHomeCard(date: date)
        case .liveHeartRate:
            if date == model.today { LiveHeartRateHomeCard() }
        case .metric:
            MetricLargeCard(key: spec.metricKey, days: spec.days, date: date)
        case .stack:
            // A stack has no large size (CardSize.sizes); a stored one shows as medium.
            SmartStackView(entries: spec.options.stack ?? [], size: .medium, date: date, rotate: spec.options.rotate ?? true)
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
        // Google's VO2 max can be an estimate from your profile rather than a measurement.
        let estimated = key == "vo2max" && (day.bool("vo2max_estimated") == true || day.string("vo2max_method") == "GOOGLE_DEMOGRAPHIC")
        let avg = base.map { "30d avg \(def.formatted($0, withUnit: false))" }
        // "So far" is said once, in the Activity header.
        return NavigationLink(value: DetailRoute.metric(key)) {
            MetricTile(title: def.shortLabel, value: def.formatted(value),
                       sub: soFar ? nil : estimated ? ["estimated", avg].compactMap { $0 }.joined(separator: " · ") : avg,
                       icon: def.icon, color: def.category.color, change: change, better: def.better)
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(soFar ? "so far" : ""))
    }

    @ViewBuilder private func vitalsCard(_ day: DayRecord) -> some View {
        let keys = (spec.options.metrics ?? VitalsGlance.keys).filter(model.recorded.contains)
        if !keys.isEmpty {
            Card {
                SectionHeader(title: "Vitals", subtitle: "Measured overnight, compared with your 30-day average")
                TwoColumnTiles(items: keys) { key in
                    tile(key, day)
                }
            }
        } else {
            Card {
                SectionHeader(title: "Vitals")
                Text("No vitals recorded yet.")
                    .font(.footnote)
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }

    private func activityCard(_ day: DayRecord) -> some View {
        let steps = day.double("steps")
        let goal = Double(model.status?.settings.stepGoal ?? 10000)
        let keys = (spec.options.metrics ?? ActivityGlance.keys).filter(model.recorded.contains)
        return Card {
            SectionHeader(title: "Activity", subtitle: date >= model.today ? "So far today" : nil)
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
        if wear == 0 { return "No heart rate this day (the band wasn't worn), so its totals are left out of your averages." }
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
        } else {
            Card {
                SectionHeader(title: "Workouts")
                if detail == nil && !model.failedDays.contains(date) {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    Text(date == model.today ? "No workouts yet today." : "No workouts this day.")
                        .font(.footnote)
                        .foregroundStyle(Theme.tertiary)
                }
            }
        }
    }
}

/// A small or medium Home card opened at full size.
struct HomeCardDetailView: View {
    let spec: HomeCardSpec
    let date: String
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            HomeLargeCard(spec: spec, date: date)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
        }
        .screenBackground()
        .navigationTitle(spec.card == .metric ? (MetricCatalog.def(spec.metricKey)?.label ?? spec.card.title) : spec.card.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: date) { await model.loadDay(date) }
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
