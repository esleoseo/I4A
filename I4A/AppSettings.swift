import Foundation

/// The time limit as set on the admin page.
struct AdminPolicy: Codable, Equatable {
    /// The user can't change the time limit in the app.
    var locked: Bool
    var limitEnabled: Bool
    var dailyLimitMinutes: Int
    /// When the admin last changed something; nil if never.
    var updatedAt: String?

    var isValid: Bool { AppSettings.allowedMinutes.contains(dailyLimitMinutes) }
}

/// User preferences, persisted in UserDefaults.
final class AppSettings: ObservableObject {
    static let limitOptions = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180]
    static let allowedMinutes = 1...1440
    static let defaultLimitMinutes = 30

    private enum Keys {
        static let hideReels = "settings.hideReels"
        static let limitEnabled = "settings.limitEnabled"
        static let dailyLimitMinutes = "settings.dailyLimitMinutes"
        static let managedByAdmin = "admin.locked"
        static let lastAdminUpdate = "admin.updatedAt"
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

    /// The admin locked the time limit; the app's limit controls are disabled.
    /// Persisted so the lock holds while offline.
    @Published private(set) var isManagedByAdmin: Bool {
        didSet { defaults.set(isManagedByAdmin, forKey: Keys.managedByAdmin) }
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
        dailyLimitMinutes = Self.allowedMinutes.contains(minutes) ? minutes : Self.defaultLimitMinutes
        isManagedByAdmin = defaults.bool(forKey: Keys.managedByAdmin)
    }

    var dailyLimitSeconds: Int { dailyLimitMinutes * 60 }

    func isLimitReached(usedSeconds: Int) -> Bool {
        limitEnabled && usedSeconds >= dailyLimitSeconds
    }

    func remainingSeconds(usedSeconds: Int) -> Int {
        max(0, dailyLimitSeconds - usedSeconds)
    }

    /// Takes the admin's values whenever the admin changed them, and keeps
    /// enforcing them for as long as the limit is locked.
    func apply(_ policy: AdminPolicy) {
        guard policy.isValid else { return }
        let lastUpdate = defaults.string(forKey: Keys.lastAdminUpdate)
        let isNewChange = policy.updatedAt != nil && policy.updatedAt != lastUpdate
        if isNewChange || policy.locked {
            if limitEnabled != policy.limitEnabled { limitEnabled = policy.limitEnabled }
            if dailyLimitMinutes != policy.dailyLimitMinutes { dailyLimitMinutes = policy.dailyLimitMinutes }
        }
        if isNewChange { defaults.set(policy.updatedAt, forKey: Keys.lastAdminUpdate) }
        if isManagedByAdmin != policy.locked { isManagedByAdmin = policy.locked }
    }
}
