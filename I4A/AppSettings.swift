import Foundation

/// The time limit as set on the admin page.
struct AdminPolicy: Codable, Equatable {
    /// The user can't change the time limit in the app.
    var locked: Bool
    /// Reels hiding is forced on and the user can't switch it off.
    var reelsLocked: Bool
    var limitEnabled: Bool
    var dailyLimitMinutes: Int
    /// When the admin last changed something; nil if never.
    var updatedAt: String?
    /// Accounts whose 1:1 DMs may show the Reels they send; nil if the
    /// server doesn't send the list (older deployments).
    var dmReelAllowlist: [String]?

    init(locked: Bool, reelsLocked: Bool = false, limitEnabled: Bool, dailyLimitMinutes: Int,
         updatedAt: String?, dmReelAllowlist: [String]? = nil) {
        self.locked = locked
        self.reelsLocked = reelsLocked
        self.dmReelAllowlist = dmReelAllowlist
        self.limitEnabled = limitEnabled
        self.dailyLimitMinutes = dailyLimitMinutes
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        locked = try c.decode(Bool.self, forKey: .locked)
        // Servers deployed before this field existed don't send it.
        reelsLocked = try c.decodeIfPresent(Bool.self, forKey: .reelsLocked) ?? false
        limitEnabled = try c.decode(Bool.self, forKey: .limitEnabled)
        dailyLimitMinutes = try c.decode(Int.self, forKey: .dailyLimitMinutes)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        dmReelAllowlist = try c.decodeIfPresent([String].self, forKey: .dmReelAllowlist)
    }

    var isValid: Bool { AppSettings.allowedMinutes.contains(dailyLimitMinutes) }
}

/// User preferences, persisted in UserDefaults.
final class AppSettings: ObservableObject {
    static let limitOptions = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180]
    static let allowedMinutes = 1...1440
    static let defaultLimitMinutes = 30
    static let defaultDMReelAllowlist = ["esleoseo", "seoleims"]
    static let maxDMReelAllowlist = 20

    /// Lowercased Instagram usernames without "@", invalid and duplicate ones dropped.
    static func normalizedUsernames(_ names: [String]) -> [String] {
        var result: [String] = []
        for name in names {
            var value = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if value.hasPrefix("@") { value.removeFirst() }
            let valid = (1...30).contains(value.count) &&
                value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_") }
            if valid && !result.contains(value) { result.append(value) }
        }
        return Array(result.prefix(maxDMReelAllowlist))
    }

    private enum Keys {
        static let hideReels = "settings.hideReels"
        static let limitEnabled = "settings.limitEnabled"
        static let dailyLimitMinutes = "settings.dailyLimitMinutes"
        static let managedByAdmin = "admin.locked"
        static let reelsManagedByAdmin = "admin.reelsLocked"
        static let lastAdminUpdate = "admin.updatedAt"
        static let dmReelAllowlist = "admin.dmReelAllowlist"
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

    /// The admin forces Reels hiding on; the app's Reels switch is disabled.
    @Published private(set) var isReelsManagedByAdmin: Bool {
        didSet { defaults.set(isReelsManagedByAdmin, forKey: Keys.reelsManagedByAdmin) }
    }

    /// Accounts whose 1:1 DMs may show the Reels they send, one per tap.
    /// Set by the admin; defaults to `defaultDMReelAllowlist`.
    @Published private(set) var dmReelAllowlist: [String] {
        didSet { defaults.set(dmReelAllowlist, forKey: Keys.dmReelAllowlist) }
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
        isReelsManagedByAdmin = defaults.bool(forKey: Keys.reelsManagedByAdmin)
        let stored = defaults.stringArray(forKey: Keys.dmReelAllowlist)
        dmReelAllowlist = stored.map(Self.normalizedUsernames) ?? Self.defaultDMReelAllowlist
        if isReelsManagedByAdmin { hideReels = true }
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
        if policy.reelsLocked && !hideReels { hideReels = true }
        if isReelsManagedByAdmin != policy.reelsLocked { isReelsManagedByAdmin = policy.reelsLocked }
        if let list = policy.dmReelAllowlist {
            let normalized = Self.normalizedUsernames(list)
            if normalized != dmReelAllowlist { dmReelAllowlist = normalized }
        }
    }
}
