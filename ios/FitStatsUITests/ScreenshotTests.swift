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
        app.swipeUp()
        shot("04-today-4")
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
            for _ in 0..<6 where !workout.isHittable { app.swipeUp() }
            workout.tap()
            shot("26-workout")
            app.swipeUp()
            shot("27-workout-2")
            back(app)
        } else {
            XCTFail("no workout in the last 7 days of fixtures")
        }
    }
}
