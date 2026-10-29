import Foundation

/// User preferences, persisted in UserDefaults.
final class AppSettings: ObservableObject {
    static let limitOptions = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180]
    static let defaultLimitMinutes = 30

    private enum Keys {
        static let hideReels = "settings.hideReels"
        static let limitEnabled = "settings.limitEnabled"
        static let dailyLimitMinutes = "settings.dailyLimitMinutes"
    }

    private let defaults: UserDefaults

    @Published var hideReels: Bool {
        didSet { defaults.set(hideReels, forKey: Keys.hideReels) }
    }

    @Published var limitEnabled: Bool {
        didSet { defaults.set(limitEnabled, forKey: Keys.limitEnabled) }
    }

    @Published var dailyLimitMinutes: Int {
        didSet { defaults.set(dailyLimitMinutes, forKey: Keys.dailyLimitMinutes) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.hideReels: true,
            Keys.limitEnabled: true,
            Keys.dailyLimitMinutes: Self.defaultLimitMinutes,
        ])
        hideReels = defaults.bool(forKey: Keys.hideReels)
        limitEnabled = defaults.bool(forKey: Keys.limitEnabled)
        let minutes = defaults.integer(forKey: Keys.dailyLimitMinutes)
        dailyLimitMinutes = Self.limitOptions.contains(minutes) ? minutes : Self.defaultLimitMinutes
    }

    var dailyLimitSeconds: Int { dailyLimitMinutes * 60 }

    func isLimitReached(usedSeconds: Int) -> Bool {
        limitEnabled && usedSeconds >= dailyLimitSeconds
    }

    func remainingSeconds(usedSeconds: Int) -> Int {
        max(0, dailyLimitSeconds - usedSeconds)
    }
}
