import SwiftUI

@main
struct I4AApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var tracker: UsageTracker
    @StateObject private var web: WebController

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _tracker = StateObject(wrappedValue: UsageTracker())
        _web = StateObject(wrappedValue: WebController(hideReels: settings.hideReels))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(tracker)
                .environmentObject(web)
        }
    }
}
