import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var tracker: UsageTracker
    @EnvironmentObject private var web: WebController
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false

    private var isBlocked: Bool {
        settings.isLimitReached(usedSeconds: tracker.usedSeconds)
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(showSettings: $showSettings)
            Divider()
            ZStack {
                InstagramWebView(webView: web.webView)
                if let message = web.loadError, !isBlocked {
                    LoadErrorView(message: message, retry: web.retry)
                }
                if isBlocked {
                    LimitReachedView(showSettings: $showSettings)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isBlocked)
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
            if phase == .active { web.appDidBecomeActive() }
        }
        .onChange(of: settings.hideReels) { hide in
            web.setHideReels(hide)
        }
    }

    private func syncState() {
        let active = scenePhase == .active
        web.setSuspended(isBlocked)
        if showSettings { web.pauseMedia() }
        tracker.update(active: active, counting: !isBlocked && !showSettings)
    }
}

private struct TopBar: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var tracker: UsageTracker
    @Binding var showSettings: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("I4A")
                .font(.system(.headline, design: .rounded).weight(.heavy))
            Spacer(minLength: 8)
            usageLabel
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("설정")
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var usageLabel: some View {
        if settings.limitEnabled {
            let remaining = settings.remainingSeconds(usedSeconds: tracker.usedSeconds)
            Text("남은 시간 \(TimeFormat.short(remaining))")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundColor(remaining <= 60 ? .red : (remaining <= 300 ? .orange : .secondary))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color(.secondarySystemBackground)))
        } else {
            Text("오늘 \(TimeFormat.short(tracker.usedSeconds)) 사용")
                .font(.subheadline.monospacedDigit())
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
