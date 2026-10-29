import SwiftUI

@main
struct I4AApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var tracker: UsageTracker
    @StateObject private var web: WebController
    @StateObject private var adminSync: AdminSync

    init() {
        let settings = AppSettings()
        let tracker = UsageTracker()
        _settings = StateObject(wrappedValue: settings)
        _tracker = StateObject(wrappedValue: tracker)
        _web = StateObject(wrappedValue: WebController(
            hideReels: settings.hideReels,
            dmReelAllowlist: settings.dmReelAllowlist
        ))
        _adminSync = StateObject(wrappedValue: AdminSync(settings: settings, tracker: tracker))
        InstagramApp.requestNotificationPermission()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
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
