import XCTest

/// Walks through every screen with fixture data and saves screenshots.
/// CI passes FITSTATS_FIXTURES and SCREENSHOT_DIR via TEST_RUNNER_ environment variables.
final class ScreenshotTests: XCTestCase {
    private var outDir: URL?

    override func setUpWithError() throws {
        continueAfterFailure = true
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty {
            let url = URL(fileURLWithPath: dir)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            outDir = url
        }
    }

    private func shot(_ name: String) {
        sleep(1)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let outDir {
            try? screenshot.pngRepresentation.write(to: outDir.appendingPathComponent("\(name).png"))
        }
    }

    private func back(_ app: XCUIApplication) {
        let button = app.navigationBars.buttons.firstMatch
        if button.exists { button.tap() }
    }

    private func open(_ app: XCUIApplication, _ id: String, _ names: [String]) {
        let element = app.buttons[id]
        guard element.waitForExistence(timeout: 5) else {
            XCTFail("missing \(id)")
            return
        }
        element.tap()
        for (index, name) in names.enumerated() {
            if index > 0 { app.swipeUp() }
            shot(name)
        }
        back(app)
        _ = app.buttons["ring-recovery"].waitForExistence(timeout: 5)
    }

    /// Swipes up until the element is on screen, then drags its top up under the navigation bar
    /// so the whole card is in the shot.
    private func reveal(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0..<10 where !onScreen(app, element) { app.swipeUp() }
        guard onScreen(app, element) else { return }
        let window = app.windows.firstMatch.frame
        let distance = element.frame.minY - (window.minY + window.height * 0.14)
        guard distance > 20 else { return }
        scrollPage(app, by: distance)
    }

    /// Drags the page by about `dy` points (positive goes further down the page) and holds
    /// still before lifting, so it doesn't fling. It starts left of the middle, clear of edit
    /// mode's remove buttons and resize handles, which a swipe from the middle can catch.
    private func scrollPage(_ app: XCUIApplication, by dy: CGFloat) {
        let window = app.windows.firstMatch.frame
        let d = Swift.max(-window.height * 0.45, Swift.min(window.height * 0.45, dy))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: d > 0 ? 0.75 : 0.3))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -d)),
                    withVelocity: .default, thenHoldForDuration: 0.3)
    }

    /// Back to the top of Home in edit mode, where the time-of-day switch is.
    private func editTop(_ app: XCUIApplication) {
        let toggle = app.switches["home-time-of-day"]
        let window = app.windows.firstMatch.frame
        for _ in 0..<25 where !(toggle.exists && toggle.frame.minY > window.minY + 100) {
            scrollPage(app, by: -window.height)
        }
    }

    private func describe(_ element: XCUIElement) -> String {
        "\(element.identifier): exists \(element.exists), frame \(element.frame)"
    }

    /// Scrolls until the middle of `element` is near the middle of the screen.
    private func scrollTo(_ app: XCUIApplication, _ element: XCUIElement) {
        let window = app.windows.firstMatch.frame
        for _ in 0..<40 where !onScreen(app, element) {
            if element.exists, !element.frame.isEmpty {
                let before = element.frame.midY
                let dy = before - (window.minY + window.height * 0.45)
                scrollPage(app, by: dy)
                trace("scroll \(element.identifier) by \(Int(dy)): midY \(Int(before)) -> \(Int(element.frame.midY))")
            } else {
                scrollPage(app, by: window.height * 0.4)
            }
        }
        trace("scrolled to \(describe(element)), on screen \(onScreen(app, element))")
    }

    /// Scroll diagnostics, saved next to the screenshots (scroll-log.txt).
    private func trace(_ line: String) {
        guard let outDir else { return }
        let url = outDir.appendingPathComponent("scroll-log.txt")
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    /// Its middle is between the navigation bar and the tab bar (isHittable also holds for an
    /// element mostly under the navigation bar, where a press opens Notification Center).
    private func onScreen(_ app: XCUIApplication, _ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let window = app.windows.firstMatch.frame
        let f = element.frame
        return !f.isEmpty && f.midY > window.minY + 120 && f.midY < window.maxY - 120
    }

    private func middle(_ element: XCUIElement, dy: CGFloat = 0.5) -> XCUICoordinate {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: dy))
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func test01ConnectScreen() {
        let app = XCUIApplication()
        app.launchEnvironment["FITSTATS_FIXTURES"] = ""
        app.launch()
        _ = app.buttons["Connect Google Health"].waitForExistence(timeout: 10)
        shot("00-connect")
        app.terminate()
    }

    func test02AllScreens() {
        let fixtures = ProcessInfo.processInfo.environment["FITSTATS_FIXTURES"] ?? ""
        XCTAssertFalse(fixtures.isEmpty, "FITSTATS_FIXTURES is not set")
        let app = XCUIApplication()
        app.launchEnvironment["FITSTATS_FIXTURES"] = fixtures
        app.launch()
        XCTAssertTrue(app.buttons["ring-recovery"].waitForExistence(timeout: 15), "Today screen did not load")

        shot("01-today")
        app.swipeUp()
        shot("02-today-2")
        app.swipeUp()
        shot("03-today-3")
        for _ in 0..<5 { app.swipeDown() }

        // Live heart rate (fixture mode simulates the band; the simulator has no Bluetooth).
        let liveButton = app.buttons["open-live-hr"]
        if liveButton.waitForExistence(timeout: 5) {
            liveButton.tap()
            _ = app.descendants(matching: .any).matching(identifier: "live-hr").firstMatch.waitForExistence(timeout: 5)
            sleep(2)
            shot("46-live-hr")
            back(app)
            _ = app.buttons["ring-recovery"].waitForExistence(timeout: 5)
        } else {
            XCTFail("missing open-live-hr")
        }

        open(app, "ring-recovery", ["05-recovery", "06-recovery-2"])
        open(app, "ring-sleep", ["07-sleep", "08-sleep-2", "09-sleep-3"])
        open(app, "ring-strain", ["10-strain", "11-strain-2"])
        open(app, "ring-stress", ["12-stress"])

        app.tabBars.buttons["Trends"].tap()
        shot("13-trends")
        app.swipeUp()
        shot("14-trends-2")
        for _ in 0..<3 { app.swipeDown() }
        let hrv = app.buttons["metric-hrv_rmssd"]
        if hrv.waitForExistence(timeout: 5) {
            hrv.tap()
            shot("15-metric-hrv")
            app.swipeUp()
            shot("16-metric-hrv-2")
            back(app)
        }

        app.tabBars.buttons["Insights"].tap()
        shot("17-insights")
        app.swipeUp()
        shot("18-insights-2")

        app.tabBars.buttons["Coach"].tap()
        shot("19-coach")
        app.swipeUp()
        shot("20-coach-2")
        let history = app.buttons["coach-history"]
        if history.waitForExistence(timeout: 5) {
            history.tap()
            let thread = app.buttons["coach-thread"].firstMatch
            if thread.waitForExistence(timeout: 5) {
                thread.tap()
                shot("21-coach-chat")
            } else {
                XCTFail("no coach conversation in the history sheet")
            }
        }

        app.tabBars.buttons["Settings"].tap()
        shot("22-settings")
        app.swipeUp()
        shot("23-settings-2")
        app.swipeUp()
        shot("24-settings-3")

        // Journal sheet, then the nearest day with a workout and its detail.
        app.tabBars.buttons["Today"].tap()
        let edit = app.buttons["journal-edit"]
        if edit.waitForExistence(timeout: 5) {
            edit.tap()
            shot("25-journal")
            app.buttons["Cancel"].tap()
        } else {
            XCTFail("missing journal-edit")
        }
        let workout = app.buttons["workout-row"].firstMatch
        for _ in 0..<6 where !workout.exists {
            app.buttons["Previous day"].tap()
            sleep(1)
        }
        if workout.exists {
            // A past day: no Tonight card, a "Log day" journal (make-fixtures leaves this day unlogged).
            shot("04-today-past-day")
            for _ in 0..<6 where !workout.isHittable { app.swipeUp() }
            shot("28-today-workouts")
            workout.tap()
            shot("26-workout")
            app.swipeUp()
            shot("27-workout-2")
            back(app)
        } else {
            XCTFail("no workout in the last 7 days of fixtures")
        }
    }

    /// Every Home card (FITSTATS_HOME_CARDS=all) at its default size and a Smart Stack swiped,
    /// then edit mode opened by holding a card: the wobbling grid, a resize by dragging the
    /// corner handle, a Metric card's and a stack's settings, a card dropped on another to
    /// stack them, time-of-day layouts, the Add cards previews, an add.
    /// Then every card small and every card medium (FITSTATS_HOME_SIZE).
    func test03HomeCards() {
        let fixtures = ProcessInfo.processInfo.environment["FITSTATS_FIXTURES"] ?? ""
        XCTAssertFalse(fixtures.isEmpty, "FITSTATS_FIXTURES is not set")
        let app = XCUIApplication()
        app.launchEnvironment["FITSTATS_FIXTURES"] = fixtures
        app.launchEnvironment["FITSTATS_HOME_CARDS"] = "all"
        app.launch()
        XCTAssertTrue(app.buttons["ring-recovery"].waitForExistence(timeout: 15), "Today screen did not load")

        shot("30-home-all")
        for index in 1...6 {
            app.swipeUp()
            shot("3\(index)-home-all-\(index + 1)")
        }
        // A Smart Stack pages sideways to its next card.
        let stack = element(app, "home-card-stack-fixture")
        reveal(app, stack)
        if stack.exists {
            shot("65-home-stack")
            stack.swipeLeft()
            sleep(1)
            shot("66-home-stack-swiped")
        } else {
            XCTFail("missing home-card-stack-fixture")
        }
        for _ in 0..<16 { app.swipeDown() }

        let card = element(app, "home-card-scores")
        guard card.waitForExistence(timeout: 5) else {
            XCTFail("missing home-card-scores")
            return
        }
        card.press(forDuration: 0.8)
        let done = app.buttons["home-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "edit mode did not start")
        shot("38-home-edit")
        // Dragging Tonight's corner handle to the right stretches it to medium when released.
        let handle = element(app, "home-resize-tonight")
        if handle.waitForExistence(timeout: 3) {
            let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 200, dy: 10)))
            sleep(1)
            shot("47-home-edit-resized")
        } else {
            XCTFail("missing home-resize-tonight")
        }
        // Holding Vitals and dragging it onto the lower part of Activity moves it below Activity.
        let vitals = element(app, "home-card-vitals")
        let activity = element(app, "home-card-activity")
        scrollTo(app, vitals)
        if onScreen(app, vitals), onScreen(app, activity) {
            middle(vitals).press(forDuration: 0.6, thenDragTo: middle(activity, dy: 0.88),
                                 withVelocity: .default, thenHoldForDuration: 0.8)
            sleep(1)
            shot("70-home-reordered")
            XCTAssertGreaterThan(vitals.frame.minY, activity.frame.minY, "Vitals did not move below Activity")
        } else {
            XCTFail("vitals or activity not reachable for reordering: \(describe(vitals)); \(describe(activity))")
        }
        // Tapping a card while editing opens its settings: the Metric card switches to HRV.
        let metric = element(app, "home-card-metric-fixture")
        scrollTo(app, metric)
        if onScreen(app, metric) {
            middle(metric).tap()
            let settingsDone = app.buttons["card-settings-done"]
            if settingsDone.waitForExistence(timeout: 5) {
                shot("61-card-settings-metric")
                let pick = app.buttons["card-settings-metric"]
                if pick.waitForExistence(timeout: 3) {
                    pick.tap()
                    sleep(1)
                    shot("62-metric-picker")
                    // HRV is under Heart, further down the list.
                    let hrv = app.buttons["metric-pick-hrv_rmssd"]
                    let list = app.collectionViews.firstMatch
                    for _ in 0..<6 where !(hrv.exists && hrv.isHittable) { list.swipeUp() }
                    if hrv.exists, hrv.isHittable { hrv.tap() } else { XCTFail("missing metric-pick-hrv_rmssd") }
                    sleep(1)
                    // Back to the settings if the list is still open.
                    let back = app.navigationBars["Metric"].buttons.firstMatch
                    if back.exists { back.tap() }
                    sleep(1)
                } else {
                    XCTFail("missing card-settings-metric")
                }
                if settingsDone.exists { settingsDone.tap() }
                sleep(1)
                shot("63-home-metric-hrv")
            } else {
                XCTFail("Metric card settings did not open")
            }
        } else {
            XCTFail("missing home-card-metric-fixture: \(describe(metric))")
        }
        let stackCell = element(app, "home-card-stack-fixture")
        scrollTo(app, stackCell)
        if onScreen(app, stackCell) {
            middle(stackCell).tap()
            let settingsDone = app.buttons["card-settings-done"]
            if settingsDone.waitForExistence(timeout: 5) {
                shot("64-stack-settings")
                settingsDone.tap()
                sleep(1)
            } else {
                XCTFail("Smart Stack settings did not open")
            }
        } else {
            XCTFail("missing home-card-stack-fixture in edit mode: \(describe(stackCell))")
        }
        // Dropping a card on the middle of another makes a Smart Stack of the two.
        editTop(app)
        let source = element(app, "home-card-recoveryTrend")
        let destination = element(app, "home-card-hrvTrend")
        scrollTo(app, source)
        if onScreen(app, source), onScreen(app, destination) {
            // Straight to the middle, then held there until it offers the stack.
            middle(source).press(forDuration: 1.2, thenDragTo: middle(destination),
                                 withVelocity: .default, thenHoldForDuration: 1.0)
            sleep(2)
            shot("67-home-stacked")
            XCTAssertFalse(source.exists || destination.exists, "recoveryTrend and hrvTrend did not become a stack")
        } else {
            XCTFail("recoveryTrend or hrvTrend not reachable for stacking: \(describe(source)); \(describe(destination))")
        }
        // Time-of-day layouts: each part of the day starts as a copy and can be edited apart.
        editTop(app)
        let timeOfDay = app.switches["home-time-of-day"]
        if timeOfDay.waitForExistence(timeout: 3) {
            timeOfDay.tap()
            sleep(1)
            shot("68-home-time-of-day")
            let evening = app.buttons["Evening"]
            if evening.waitForExistence(timeout: 3) {
                evening.tap()
                sleep(1)
                shot("69-home-evening-layout")
            } else {
                XCTFail("missing the Evening layout button")
            }
        } else {
            XCTFail("missing home-time-of-day")
        }
        // Every card is on Home in this mode, so Add cards is empty. Reset (kept in memory only
        // in this mode, nothing is stored) fills it with previews.
        let reset = app.buttons["home-reset"]
        scrollTo(app, reset)
        if onScreen(app, reset) {
            reset.tap()
            sleep(1)
            let addCards = app.buttons["home-add-cards"]
            if addCards.exists { addCards.tap() }
            shot("39-home-add-previews")
            // Last night is the first card in the list after a reset, so it's on screen here.
            let add = app.buttons["home-add-lastNight"]
            if add.waitForExistence(timeout: 3), add.isHittable { add.tap() } else { XCTFail("home-add-lastNight not reachable") }
            sleep(1)
            app.swipeUp()
            shot("48-home-add-previews-2")
            app.swipeUp()
            shot("49-home-add-previews-3")
        } else {
            XCTFail("home-reset not reachable: \(describe(reset))")
        }
        if done.exists { done.tap() }
        sleep(1)
        shot("50-home-after-edit")
        app.terminate()

        // Mid-resize (FITSTATS_HOLD_RESIZE keeps the stretch after the finger lifts): Journal, the
        // right card of a small pair, grows to the left, and Tonight stretches past its footprint.
        app.launchEnvironment["FITSTATS_HOLD_RESIZE"] = "1"
        app.launch()
        let scores = element(app, "home-card-scores")
        if scores.waitForExistence(timeout: 15) {
            scores.press(forDuration: 0.8)
            for (id, offset, name) in [("journal", CGVector(dx: -110, dy: 40), "71-home-resize-held-left"),
                                       ("tonight", CGVector(dx: 60, dy: 70), "72-home-resize-held")] {
                let handle = element(app, "home-resize-\(id)")
                if handle.waitForExistence(timeout: 5) {
                    let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    start.press(forDuration: 0.05, thenDragTo: start.withOffset(offset))
                    shot(name)
                } else {
                    XCTFail("missing home-resize-\(id)")
                }
            }
        } else {
            XCTFail("Today (held resize) did not load")
        }
        app.terminate()
        app.launchEnvironment["FITSTATS_HOLD_RESIZE"] = nil

        for (size, first, count) in [("small", 51, 3), ("medium", 55, 5)] {
            app.launchEnvironment["FITSTATS_HOME_SIZE"] = size
            app.launch()
            XCTAssertTrue(element(app, "home-card-scores").waitForExistence(timeout: 15), "Today (\(size)) did not load")
            sleep(1)
            shot("\(first)-home-\(size)")
            for index in 1...count {
                app.swipeUp()
                shot("\(first + index)-home-\(size)-\(index + 1)")
            }
            app.terminate()
        }
    }

    /// Training load and best bedtime on Insights, the calendar and compare periods from Trends,
    /// and a workout's heart-rate recovery.
    func test04InsightsPack() {
        let fixtures = ProcessInfo.processInfo.environment["FITSTATS_FIXTURES"] ?? ""
        XCTAssertFalse(fixtures.isEmpty, "FITSTATS_FIXTURES is not set")
        let app = XCUIApplication()
        app.launchEnvironment["FITSTATS_FIXTURES"] = fixtures
        app.launch()
        XCTAssertTrue(app.buttons["ring-recovery"].waitForExistence(timeout: 15), "Today screen did not load")

        app.tabBars.buttons["Insights"].tap()
        for (id, name) in [("training-load", "40-insights-load"), ("bedtime-card", "41-insights-bedtime")] {
            let card = element(app, id)
            if card.waitForExistence(timeout: 5) {
                reveal(app, card)
                shot(name)
            } else {
                XCTFail("missing \(id)")
            }
        }

        app.tabBars.buttons["Trends"].tap()
        for (button, screen, name) in [("open-calendar", "calendar-heatmap", "42-calendar"), ("open-compare", "compare-periods", "43-compare")] {
            let link = app.buttons[button]
            guard link.waitForExistence(timeout: 5) else {
                XCTFail("missing \(button)")
                continue
            }
            link.tap()
            XCTAssertTrue(element(app, screen).waitForExistence(timeout: 5), "\(screen) did not open")
            shot(name)
            back(app)
        }

        // The nearest day with a workout, then its heart-rate recovery card.
        app.tabBars.buttons["Today"].tap()
        let workout = app.buttons["workout-row"].firstMatch
        for _ in 0..<6 where !workout.exists {
            app.buttons["Previous day"].tap()
            sleep(1)
        }
        guard workout.exists else {
            XCTFail("no workout in the last 7 days of fixtures")
            return
        }
        for _ in 0..<6 where !workout.isHittable { app.swipeUp() }
        workout.tap()
        let recovery = element(app, "hr-recovery")
        if recovery.waitForExistence(timeout: 5) {
            reveal(app, recovery)
            shot("44-workout-hrr")
        } else {
            XCTFail("missing hr-recovery")
        }
        back(app)
    }
}
