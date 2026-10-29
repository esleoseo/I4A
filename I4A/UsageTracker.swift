import Foundation

/// Seconds of use recorded for a single calendar day.
struct UsageLedger: Equatable {
    var day: String
    var seconds: Double

    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Returns a fresh ledger when `date` falls on a different day than this one.
    func rolledOver(to date: Date, calendar: Calendar) -> UsageLedger {
        let key = Self.dayKey(for: date, calendar: calendar)
        return key == day ? self : UsageLedger(day: key, seconds: 0)
    }
}

/// Measures how long Instagram is on screen today.
///
/// Time is accumulated from a monotonic clock while `counting` is true, so
/// changing the wall clock can't add or remove time mid-session; the wall
/// clock is only used to decide which day the time belongs to.
final class UsageTracker: ObservableObject {
    @Published private(set) var usedSeconds: Int = 0

    /// Largest gap between two ticks that still counts as use. Guards against
    /// counting time the process spent suspended without a scene change.
    static let maxTickGap: TimeInterval = 10
    static let tickInterval: TimeInterval = 1
    private static let saveInterval: TimeInterval = 5

    private enum Keys {
        static let day = "usage.day"
        static let seconds = "usage.seconds"
    }

    private let defaults: UserDefaults
    private let now: () -> Date
    private let uptime: () -> TimeInterval
    private let calendar: () -> Calendar

    private var ledger: UsageLedger
    private var timer: Timer?
    private var lastTick: TimeInterval?
    private var isActive = false
    private var isCounting = false
    private var unsavedSeconds: TimeInterval = 0

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        calendar: @escaping () -> Calendar = { Calendar.current }
    ) {
        self.defaults = defaults
        self.now = now
        self.uptime = uptime
        self.calendar = calendar
        let stored = UsageLedger(
            day: defaults.string(forKey: Keys.day) ?? "",
            seconds: max(0, defaults.double(forKey: Keys.seconds))
        )
        ledger = stored.rolledOver(to: now(), calendar: calendar())
        usedSeconds = Int(ledger.seconds)
        if ledger != stored { save() }
    }

    deinit {
        timer?.invalidate()
    }

    /// - Parameters:
    ///   - active: the app is in the foreground. The clock only runs while active.
    ///   - counting: Instagram is actually usable on screen right now.
    func update(active: Bool, counting: Bool) {
        // Settle the time spent in the previous state before switching.
        tick()
        isActive = active
        isCounting = active && counting
        if active {
            if lastTick == nil { lastTick = uptime() }
            startTimer()
        } else {
            stopTimer()
            lastTick = nil
            save()
        }
    }

    func tick() {
        let t = uptime()
        let elapsed = lastTick.map { t - $0 } ?? 0
        if isActive { lastTick = t }

        var next = ledger.rolledOver(to: now(), calendar: calendar())
        let dayChanged = next.day != ledger.day
        if isCounting, elapsed > 0 {
            let counted = min(elapsed, Self.maxTickGap)
            next.seconds += counted
            unsavedSeconds += counted
        }
        ledger = next

        let whole = Int(ledger.seconds)
        if whole != usedSeconds { usedSeconds = whole }
        if dayChanged || unsavedSeconds >= Self.saveInterval { save() }
    }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 0.2
        // .common keeps the timer firing while the user is scrolling.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func save() {
        defaults.set(ledger.day, forKey: Keys.day)
        defaults.set(ledger.seconds, forKey: Keys.seconds)
        unsavedSeconds = 0
    }
}
