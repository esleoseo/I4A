import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var tracker: UsageTracker
    @Environment(\.dismiss) private var dismiss

    /// Once today's limit is reached it can't be raised or switched off until
    /// tomorrow; otherwise the limit would be one tap away from meaningless.
    private var isLocked: Bool {
        settings.isLimitReached(usedSeconds: tracker.usedSeconds)
    }

    private var limitOptions: [Int] {
        guard isLocked else { return AppSettings.limitOptions }
        return AppSettings.limitOptions.filter { $0 <= settings.dailyLimitMinutes }
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle("릴스 숨기기", isOn: $settings.hideReels)
                } footer: {
                    Text("릴스 탭, 피드의 릴스, 프로필의 릴스 탭과 릴스 게시물을 숨기고 릴스 화면으로 이동하지 못하게 막아요.")
                }

                Section {
                    Toggle("하루 사용 시간 제한", isOn: $settings.limitEnabled)
                        .disabled(isLocked)
                    if settings.limitEnabled {
                        Picker("하루 허용 시간", selection: $settings.dailyLimitMinutes) {
                            ForEach(limitOptions, id: \.self) { minutes in
                                Text(TimeFormat.short(minutes * 60)).tag(minutes)
                            }
                        }
                    }
                    HStack {
                        Text("오늘 사용한 시간")
                        Spacer()
                        Text(TimeFormat.short(tracker.usedSeconds))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                } header: {
                    Text("시간 제한")
                } footer: {
                    if isLocked {
                        Text("오늘은 제한 시간에 도달해서 제한을 늘리거나 끌 수 없어요. 자정에 초기화돼요.")
                    } else {
                        Text("앱이 화면에 켜져 있는 동안만 시간이 흘러요. 매일 자정에 초기화돼요.")
                    }
                }

                Section {
                    HStack {
                        Text("버전")
                        Spacer()
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                            .foregroundColor(.secondary)
                    }
                } footer: {
                    Text("I4A — Instagram for ADHDs")
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
