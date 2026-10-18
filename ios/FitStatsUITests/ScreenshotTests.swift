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
        for _ in 0..<10 where !element.isHittable { app.swipeUp() }
        guard element.isHittable else { return }
        let window = app.windows.firstMatch.frame
        let target = window.minY + window.height * 0.14
        let distance = element.frame.minY - target
        guard distance > 20 else { return }
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        let end = start.withOffset(CGVector(dx: 0, dy: -Swift.min(distance, window.height * 0.6)))
        start.press(forDuration: 0.1, thenDragTo: end)
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

    /// Every Home card (FITSTATS_HOME_CARDS=all), then the Home editor opened by holding a card.
    func test03HomeCards() {
        let fixtures = ProcessInfo.processInfo.environment["FITSTATS_FIXTURES"] ?? ""
        XCTAssertFalse(fixtures.isEmpty, "FITSTATS_FIXTURES is not set")
        let app = XCUIApplication()
        app.launchEnvironment["FITSTATS_FIXTURES"] = fixtures
        app.launchEnvironment["FITSTATS_HOME_CARDS"] = "all"
        app.launch()
        XCTAssertTrue(app.buttons["ring-recovery"].waitForExistence(timeout: 15), "Today screen did not load")

        shot("30-home-all")
        for index in 1...7 {
            app.swipeUp()
            shot("3\(index)-home-all-\(index + 1)")
        }
        // The last card in this mode; the swipes above may stop short of it.
        let trainingLoad = element(app, "home-card-trainingLoad")
        if trainingLoad.waitForExistence(timeout: 5) {
            reveal(app, trainingLoad)
            shot("45-home-training-load")
        } else {
            XCTFail("missing home-card-trainingLoad")
        }
        for _ in 0..<16 { app.swipeDown() }

        let card = app.descendants(matching: .any).matching(identifier: "home-card-scores").firstMatch
        guard card.waitForExistence(timeout: 5) else {
            XCTFail("missing home-card-scores")
            return
        }
        card.press(forDuration: 0.8)
        let done = app.buttons["home-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Home editor did not open")
        shot("38-home-editor")
        let list = app.collectionViews.containing(.any, identifier: "home-shown-scores").firstMatch
        let scroll = { if list.exists { list.swipeUp() } else { app.swipeUp() } }
        // Every card is on Home in this mode, so "More cards" is empty. Reset (kept in memory
        // only in this mode, nothing is stored) fills it with the add rows.
        let reset = app.buttons["home-reset"]
        for _ in 0..<5 where !(reset.exists && reset.isHittable) { scroll() }
        if reset.exists, reset.isHittable {
            reset.tap()
            let add = app.buttons["home-add-lastNight"]
            _ = add.waitForExistence(timeout: 2)
            for _ in 0..<5 where !(add.exists && add.isHittable) { scroll() }
        } else {
            XCTFail("home-reset not reachable")
        }
        shot("39-home-editor-2")
        if done.exists { done.tap() }
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
