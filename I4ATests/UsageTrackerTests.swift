import XCTest
@testable import I4A

final class UsageTrackerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var clock = Date(timeIntervalSince1970: 1_700_000_000)
    private var uptime: TimeInterval = 1_000

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }

    override func setUp() {
        super.setUp()
        suiteName = "I4ATests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        // 2023-11-15 10:00 in Seoul.
        clock = calendar.date(from: DateComponents(year: 2023, month: 11, day: 15, hour: 10))!
        uptime = 1_000
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeTracker() -> UsageTracker {
        let calendar = self.calendar
        return UsageTracker(
            defaults: defaults,
            now: { [unowned self] in self.clock },
            uptime: { [unowned self] in self.uptime },
            calendar: { calendar }
        )
    }

    private func advance(_ seconds: TimeInterval) {
        clock += seconds
        uptime += seconds
    }

    /// Lets `seconds` pass with the timer ticking once a second, as in the app.
    private func run(_ tracker: UsageTracker, seconds: Int) {
        for _ in 0..<seconds {
            advance(1)
            tracker.tick()
        }
    }

    func testCountsOnlyWhileCounting() {
        let tracker = makeTracker()
        tracker.update(active: true, counting: true)
        run(tracker, seconds: 30)
        XCTAssertEqual(tracker.usedSeconds, 30)

        tracker.update(active: true, counting: false)
        run(tracker, seconds: 100)
        XCTAssertEqual(tracker.usedSeconds, 30)

        tracker.update(active: true, counting: true)
        run(tracker, seconds: 5)
        XCTAssertEqual(tracker.usedSeconds, 35)
    }

    func testBackgroundTimeIsNotCounted() {
        let tracker = makeTracker()
        tracker.update(active: true, counting: true)
        run(tracker, seconds: 10)
        tracker.update(active: false, counting: true)
        XCTAssertEqual(tracker.usedSeconds, 10)

        advance(3_600)
        tracker.update(active: true, counting: true)
        run(tracker, seconds: 1)
        XCTAssertEqual(tracker.usedSeconds, 11)
    }

    func testLongGapBetweenTicksIsCapped() {
        let tracker = makeTracker()
        tracker.update(active: true, counting: true)
        advance(500)
        tracker.tick()
        XCTAssertEqual(tracker.usedSeconds, Int(UsageTracker.maxTickGap))
    }

    func testWallClockChangesDoNotAddTime() {
        let tracker = makeTracker()
        tracker.update(active: true, counting: true)
        clock += 7_200 // clock jumps forward, same day
        uptime += 2
        tracker.tick()
        XCTAssertEqual(tracker.usedSeconds, 2)
    }

    func testResetsOnNewDay() {
        let tracker = makeTracker()
        tracker.update(active: true, counting: true)
        run(tracker, seconds: 8)
        XCTAssertEqual(tracker.usedSeconds, 8)

        // Jump to 00:00:05 the next day while the app stays open.
        clock = calendar.date(from: DateComponents(year: 2023, month: 11, day: 16, hour: 0, second: 5))!
        uptime += 1
        tracker.tick()
        XCTAssertEqual(tracker.usedSeconds, 1)
    }

    func testPersistsAcrossLaunches() {
        let tracker = makeTracker()
        tracker.update(active: true, counting: true)
        run(tracker, seconds: 42)
        tracker.update(active: false, counting: false)

        let relaunched = makeTracker()
        XCTAssertEqual(relaunched.usedSeconds, 42)
    }

    func testStoredUsageFromAnotherDayIsDiscarded() {
        let tracker = makeTracker()
        tracker.update(active: true, counting: true)
        run(tracker, seconds: 42)
        tracker.update(active: false, counting: false)

        clock += 86_400
        let relaunched = makeTracker()
        XCTAssertEqual(relaunched.usedSeconds, 0)
    }

    func testDayKey() {
        let date = calendar.date(from: DateComponents(year: 2024, month: 3, day: 7, hour: 23, minute: 59))!
        XCTAssertEqual(UsageLedger.dayKey(for: date, calendar: calendar), "2024-03-07")
    }
}

final class AppSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "I4ATests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaults() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.hideReels)
        XCTAssertTrue(settings.limitEnabled)
        XCTAssertEqual(settings.dailyLimitMinutes, AppSettings.defaultLimitMinutes)
    }

    func testPersists() {
        let settings = AppSettings(defaults: defaults)
        settings.hideReels = false
        settings.limitEnabled = false
        settings.dailyLimitMinutes = 60

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertFalse(reloaded.hideReels)
        XCTAssertFalse(reloaded.limitEnabled)
        XCTAssertEqual(reloaded.dailyLimitMinutes, 60)
    }

    func testInvalidStoredLimitFallsBackToDefault() {
        defaults.set(0, forKey: "settings.dailyLimitMinutes")
        XCTAssertEqual(AppSettings(defaults: defaults).dailyLimitMinutes, AppSettings.defaultLimitMinutes)
        defaults.set(5_000, forKey: "settings.dailyLimitMinutes")
        XCTAssertEqual(AppSettings(defaults: defaults).dailyLimitMinutes, AppSettings.defaultLimitMinutes)
        // Values the admin may set outside the presets are kept.
        defaults.set(7, forKey: "settings.dailyLimitMinutes")
        XCTAssertEqual(AppSettings(defaults: defaults).dailyLimitMinutes, 7)
    }

    func testLimitReached() {
        let settings = AppSettings(defaults: defaults)
        settings.dailyLimitMinutes = 10
        XCTAssertFalse(settings.isLimitReached(usedSeconds: 599))
        XCTAssertTrue(settings.isLimitReached(usedSeconds: 600))
        XCTAssertEqual(settings.remainingSeconds(usedSeconds: 590), 10)
        XCTAssertEqual(settings.remainingSeconds(usedSeconds: 700), 0)
        settings.limitEnabled = false
        XCTAssertFalse(settings.isLimitReached(usedSeconds: 10_000))
    }

    func testTimeFormat() {
        XCTAssertEqual(TimeFormat.short(0), "0초")
        XCTAssertEqual(TimeFormat.short(-5), "0초")
        XCTAssertEqual(TimeFormat.short(59), "59초")
        XCTAssertEqual(TimeFormat.short(60), "1분")
        XCTAssertEqual(TimeFormat.short(1_800), "30분")
        XCTAssertEqual(TimeFormat.short(3_600), "1시간")
        XCTAssertEqual(TimeFormat.short(5_400), "1시간 30분")
    }
}
