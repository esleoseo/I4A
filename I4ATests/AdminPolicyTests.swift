import XCTest
@testable import I4A

final class AdminPolicyTests: XCTestCase {
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

    private func policy(locked: Bool, enabled: Bool = true, minutes: Int, at updatedAt: String?) -> AdminPolicy {
        AdminPolicy(locked: locked, limitEnabled: enabled, dailyLimitMinutes: minutes, updatedAt: updatedAt)
    }

    func testDecodesServerJSON() throws {
        let json = #"{"locked":true,"limitEnabled":false,"dailyLimitMinutes":45,"updatedAt":"2026-10-29T14:54:38.140Z"}"#
        let decoded = try JSONDecoder().decode(AdminPolicy.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, policy(locked: true, enabled: false, minutes: 45, at: "2026-10-29T14:54:38.140Z"))

        let fresh = #"{"locked":false,"limitEnabled":true,"dailyLimitMinutes":30,"updatedAt":null}"#
        XCTAssertNil(try JSONDecoder().decode(AdminPolicy.self, from: Data(fresh.utf8)).updatedAt)
    }

    func testLockedPolicyIsEnforced() {
        let settings = AppSettings(defaults: defaults)
        settings.apply(policy(locked: true, minutes: 45, at: "t1"))
        XCTAssertTrue(settings.isManagedByAdmin)
        XCTAssertEqual(settings.dailyLimitMinutes, 45)

        // Even if something changes the value locally, the next sync restores it.
        settings.dailyLimitMinutes = 180
        settings.apply(policy(locked: true, minutes: 45, at: "t1"))
        XCTAssertEqual(settings.dailyLimitMinutes, 45)
    }

    func testLockSurvivesRelaunch() {
        AppSettings(defaults: defaults).apply(policy(locked: true, minutes: 20, at: "t1"))
        let relaunched = AppSettings(defaults: defaults)
        XCTAssertTrue(relaunched.isManagedByAdmin)
        XCTAssertEqual(relaunched.dailyLimitMinutes, 20)
    }

    func testUnlockedPolicyAppliesOnlyNewChanges() {
        let settings = AppSettings(defaults: defaults)
        settings.apply(policy(locked: false, minutes: 60, at: "t1"))
        XCTAssertFalse(settings.isManagedByAdmin)
        XCTAssertEqual(settings.dailyLimitMinutes, 60)

        // The user changes it; the same admin state doesn't override that.
        settings.dailyLimitMinutes = 90
        settings.apply(policy(locked: false, minutes: 60, at: "t1"))
        XCTAssertEqual(settings.dailyLimitMinutes, 90)

        // A new admin change does.
        settings.apply(policy(locked: false, minutes: 15, at: "t2"))
        XCTAssertEqual(settings.dailyLimitMinutes, 15)
    }

    func testUntouchedServerDoesNotOverrideLocalSettings() {
        let settings = AppSettings(defaults: defaults)
        settings.dailyLimitMinutes = 90
        settings.apply(policy(locked: false, minutes: 30, at: nil))
        XCTAssertEqual(settings.dailyLimitMinutes, 90)
    }

    func testInvalidPolicyIsIgnored() {
        let settings = AppSettings(defaults: defaults)
        settings.apply(policy(locked: true, minutes: 0, at: "t1"))
        XCTAssertFalse(settings.isManagedByAdmin)
        XCTAssertEqual(settings.dailyLimitMinutes, AppSettings.defaultLimitMinutes)
    }

    func testUnlockKeepsAdminValues() {
        let settings = AppSettings(defaults: defaults)
        settings.apply(policy(locked: true, enabled: false, minutes: 45, at: "t1"))
        settings.apply(policy(locked: false, enabled: false, minutes: 45, at: "t2"))
        XCTAssertFalse(settings.isManagedByAdmin)
        XCTAssertFalse(settings.limitEnabled)
        settings.limitEnabled = true
        XCTAssertTrue(settings.limitEnabled)
    }

    func testReelsLockForcesHidingAndSurvivesRelaunch() {
        let settings = AppSettings(defaults: defaults)
        settings.hideReels = false
        settings.apply(AdminPolicy(locked: false, reelsLocked: true, limitEnabled: true, dailyLimitMinutes: 30, updatedAt: "t1"))
        XCTAssertTrue(settings.hideReels)
        XCTAssertTrue(settings.isReelsManagedByAdmin)

        let relaunched = AppSettings(defaults: defaults)
        XCTAssertTrue(relaunched.isReelsManagedByAdmin)
        XCTAssertTrue(relaunched.hideReels)

        relaunched.apply(AdminPolicy(locked: false, reelsLocked: false, limitEnabled: true, dailyLimitMinutes: 30, updatedAt: "t2"))
        XCTAssertFalse(relaunched.isReelsManagedByAdmin)
        relaunched.hideReels = false
        XCTAssertFalse(relaunched.hideReels)
    }

    func testDecodesPolicyWithoutReelsLock() throws {
        let json = #"{"locked":false,"limitEnabled":true,"dailyLimitMinutes":30,"updatedAt":null}"#
        XCTAssertFalse(try JSONDecoder().decode(AdminPolicy.self, from: Data(json.utf8)).reelsLocked)
        let locked = #"{"locked":false,"reelsLocked":true,"limitEnabled":true,"dailyLimitMinutes":30,"updatedAt":null}"#
        XCTAssertTrue(try JSONDecoder().decode(AdminPolicy.self, from: Data(locked.utf8)).reelsLocked)
    }

    func testDMReelAllowlistDefaultsAndAdminUpdates() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.dmReelAllowlist, ["esleoseo", "seoleims"])

        // An older server without the field leaves the list alone.
        settings.apply(policy(locked: false, minutes: 30, at: "t1"))
        XCTAssertEqual(settings.dmReelAllowlist, ["esleoseo", "seoleims"])

        settings.apply(AdminPolicy(locked: false, limitEnabled: true, dailyLimitMinutes: 30,
                                   updatedAt: "t2", dmReelAllowlist: ["@New.Friend", "bad name!", "new.friend"]))
        XCTAssertEqual(settings.dmReelAllowlist, ["new.friend"])
        XCTAssertEqual(AppSettings(defaults: defaults).dmReelAllowlist, ["new.friend"])

        // An empty list from the admin means no exceptions.
        settings.apply(AdminPolicy(locked: false, limitEnabled: true, dailyLimitMinutes: 30,
                                   updatedAt: "t3", dmReelAllowlist: []))
        XCTAssertEqual(settings.dmReelAllowlist, [])
        XCTAssertEqual(AppSettings(defaults: defaults).dmReelAllowlist, [])
    }

    func testDecodesDMReelAllowlist() throws {
        let json = #"{"locked":false,"limitEnabled":true,"dailyLimitMinutes":30,"updatedAt":null,"dmReelAllowlist":["esleoseo"]}"#
        XCTAssertEqual(try JSONDecoder().decode(AdminPolicy.self, from: Data(json.utf8)).dmReelAllowlist, ["esleoseo"])
    }

    func testNormalizedUsernames() {
        XCTAssertEqual(AppSettings.normalizedUsernames([" @EsLeoSeo ", "seoleims", "seoleims", "", "a b", "x".padding(toLength: 31, withPad: "x", startingAt: 0)]),
                       ["esleoseo", "seoleims"])
    }
}
