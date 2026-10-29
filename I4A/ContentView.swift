import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var tracker: UsageTracker
    @EnvironmentObject private var web: WebController
    @EnvironmentObject private var adminSync: AdminSync
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showReelNotice = false
    @State private var noticeToken = 0
    @State private var showInstagramNotice = false
    /// Launched or back from the background since the last check. Brief
    /// inactive spells (permission prompts, the photo picker, Control
    /// Center) don't count.
    @State private var isFreshlyOpened = true

    private var isBlocked: Bool {
        settings.isLimitReached(usedSeconds: tracker.usedSeconds)
    }

    private var showsTabBar: Bool {
        !web.tabs.isEmpty && !web.pageHidesBar && web.loadError == nil && !isBlocked
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(showSettings: $showSettings)
            ZStack(alignment: .bottom) {
                // Runs under the home indicator: no dead strip at the bottom.
                InstagramWebView(controller: web)
                    .ignoresSafeArea(.container, edges: .bottom)
                if showsTabBar {
                    FloatingTabBar(
                        tabs: web.tabs,
                        active: web.activeTab,
                        collapsed: web.isBarCollapsed,
                        select: web.select
                    )
                    .padding(.bottom, web.isBarCollapsed ? 0 : 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if showInstagramNotice {
                    // A banner rather than an alert: a modal alert colliding
                    // with another presentation (a permission prompt, the photo
                    // picker) could leave the screen unable to take touches.
                    InstagramInstalledBanner { showInstagramNotice = false }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if showReelNotice {
                    ReelNotice()
                        .padding(.bottom, showsTabBar ? 84 : 24)
                        .transition(.opacity)
                }
                if let message = web.loadError, !isBlocked {
                    LoadErrorView(message: message, retry: web.retry)
                        .ignoresSafeArea(.container, edges: .bottom)
                }
                if isBlocked {
                    LimitReachedView(showSettings: $showSettings)
                        .ignoresSafeArea(.container, edges: .bottom)
                        .transition(.opacity)
                }
            }
        }
        // The keyboard covers the bar instead of pushing it up.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .animation(.easeInOut(duration: 0.25), value: isBlocked)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showsTabBar)
        .animation(.easeInOut(duration: 0.2), value: showReelNotice)
        .animation(.easeInOut(duration: 0.25), value: showInstagramNotice)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(tracker)
        }
        .onAppear(perform: syncState)
        .onChange(of: isBlocked) { _ in syncState() }
        .onChange(of: showSettings) { _ in syncState() }
        .onChange(of: scenePhase) { phase in
            syncState()
            switch phase {
            case .active:
                web.appDidBecomeActive()
                InstagramApp.appDidBecomeActive()
                if isFreshlyOpened {
                    isFreshlyOpened = false
                    // Never on top of something already showing, e.g. the
                    // picker Instagram opens to add a story.
                    if InstagramApp.isInstalled { showInstagramNotice = true }
                }
            case .background:
                isFreshlyOpened = true
                InstagramApp.appDidEnterBackground()
            default:
                break
            }
        }
        .onChange(of: settings.hideReels) { hide in
            web.setHideReels(hide)
        }
        .onChange(of: web.blockedReelCount) { _ in
            showReelNotice = true
            noticeToken += 1
            let token = noticeToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if token == noticeToken { showReelNotice = false }
            }
        }
    }

    private func syncState() {
        let active = scenePhase == .active
        web.setSuspended(isBlocked)
        if showSettings { web.pauseMedia() }
        tracker.update(active: active, counting: !isBlocked && !showSettings)
        adminSync.setActive(active)
    }
}

private struct TopBar: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var tracker: UsageTracker
    @Binding var showSettings: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text("I4A")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(.secondary)
            Spacer(minLength: 6)
            usageLabel
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    // Small to look at, still a comfortable target.
                    .frame(width: 36, height: 26)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("설정")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: 26)
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var usageLabel: some View {
        if settings.limitEnabled {
            let remaining = settings.remainingSeconds(usedSeconds: tracker.usedSeconds)
            Text("남은 시간 \(TimeFormat.short(remaining))")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundColor(remaining <= 60 ? .red : (remaining <= 300 ? .orange : .secondary))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color(.secondarySystemBackground)))
        } else {
            Text("오늘 \(TimeFormat.short(tracker.usedSeconds)) 사용")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
        }
    }
}

private struct LoadErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text(message)
                .multilineTextAlignment(.center)
            Button("다시 시도", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

enum TimeFormat {
    /// "1시간 5분", "12분", "45초".
    static func short(_ seconds: Int) -> String {
        let s = max(0, seconds)
        if s < 60 { return "\(s)초" }
        let hours = s / 3600
        let minutes = (s % 3600) / 60
        if hours == 0 { return "\(minutes)분" }
        return minutes == 0 ? "\(hours)시간" : "\(hours)시간 \(minutes)분"
    }
}
