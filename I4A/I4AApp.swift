import SwiftUI

@main
struct I4AApp: App {
    // Held, not observed: each view observes only what it shows. Observed
    // here, every tick of the usage clock (once a second) and every change
    // of the bar would rebuild the whole window.
    @State private var settings: AppSettings
    @State private var tracker: UsageTracker
    @State private var web: WebController
    @State private var adminSync: AdminSync

    init() {
        let settings = AppSettings()
        let tracker = UsageTracker()
        _settings = State(initialValue: settings)
        _tracker = State(initialValue: tracker)
        _web = State(initialValue: WebController(hideReels: settings.hideReels))
        _adminSync = State(initialValue: AdminSync(settings: settings, tracker: tracker))
        InstagramApp.requestNotificationPermission()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                tracker: tracker,
                initiallyBlocked: settings.isLimitReached(usedSeconds: tracker.usedSeconds)
            )
                .environmentObject(settings)
                .environmentObject(tracker)
                .environmentObject(web)
                .environmentObject(adminSync)
        }
        .backgroundTask(.appRefresh(InstagramApp.refreshTaskID)) {
            await InstagramApp.runBackgroundCheck()
        }
    }
}
