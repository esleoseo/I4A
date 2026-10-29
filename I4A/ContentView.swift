import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var tracker: UsageTracker
    @EnvironmentObject private var web: WebController
    @EnvironmentObject private var adminSync: AdminSync
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showAbout = false
    @State private var showReelNotice = false
    @State private var noticeToken = 0

    private var isBlocked: Bool {
        settings.isLimitReached(usedSeconds: tracker.usedSeconds)
    }

    private var showsTabBar: Bool {
        !web.tabs.isEmpty && !web.pageHidesBar && web.loadError == nil && !isBlocked
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(showSettings: $showSettings, showAbout: $showAbout)
            ZStack(alignment: .bottom) {
                // Runs under the home indicator: no dead strip at the bottom.
                InstagramWebView(controller: web)
                    .ignoresSafeArea(.container, edges: .bottom)
                if showsTabBar {
                    FloatingTabBar(
                        tabs: web.tabs,
                        active: web.activeTab,
                        collapsed: web.isBarCollapsed,
                        avatarURL: web.profileImageURL,
                        select: web.select
                    )
                    .padding(.bottom, web.isBarCollapsed ? 0 : 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
        .overlay {
            if showAbout {
                AboutView { showAbout = false }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showAbout)
        .animation(.easeInOut(duration: 0.25), value: isBlocked)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showsTabBar)
        .animation(.easeInOut(duration: 0.2), value: showReelNotice)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(tracker)
                .environmentObject(adminSync)
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
            case .background:
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
    @Binding var showAbout: Bool

    var body: some View {
        HStack(spacing: 6) {
            Button {
                showAbout = true
            } label: {
                Text("I4A")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(.secondary)
                    .frame(height: 26)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("앱 정보")
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

/// App info, centred. A card of its own rather than a system alert, whose
/// text iOS 26 aligns to the left.
private struct AboutView: View {
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text("Instagram for ADHDs")
                        .font(.headline)
                    Text("이레와 함께하는 은성오빠의 사랑으로 제작됨")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 22)
                Divider()
                Button(action: dismiss) {
                    Text("확인")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                }
            }
            .frame(maxWidth: 300)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 40)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }
}
