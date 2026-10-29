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
        // The admin may have set a value outside the presets.
        var options = Set(AppSettings.limitOptions)
        options.insert(settings.dailyLimitMinutes)
        let sorted = options.sorted()
        guard isLocked else { return sorted }
        return sorted.filter { $0 <= settings.dailyLimitMinutes }
    }

    /// "@a, @b"
    private var allowedAccounts: String {
        settings.dmReelAllowlist.map { "@" + $0 }.joined(separator: ", ")
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle("릴스 숨기기", isOn: $settings.hideReels)
                        .disabled(settings.isReelsManagedByAdmin)
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if settings.isReelsManagedByAdmin {
                            Label("관리자가 릴스를 숨기도록 잠갔어요. 앱에서는 바꿀 수 없어요.", systemImage: "lock.fill")
                        } else {
                            Text("릴스 탭, 피드의 릴스, 프로필의 릴스 탭과 릴스 게시물을 숨기고 릴스 화면으로 이동하지 못하게 막아요.")
                        }
                        if settings.hideReels && !settings.dmReelAllowlist.isEmpty {
                            Text("예외: 다음 계정과의 1:1 DM에서 받은 릴스는 탭할 때마다 한 편씩 볼 수 있어요. \(allowedAccounts)")
                        }
                    }
                }

                Section {
                    Group {
                        Toggle("하루 사용 시간 제한", isOn: $settings.limitEnabled)
                            .disabled(isLocked)
                        if settings.limitEnabled {
                            Picker("하루 허용 시간", selection: $settings.dailyLimitMinutes) {
                                ForEach(limitOptions, id: \.self) { minutes in
                                    Text(TimeFormat.short(minutes * 60)).tag(minutes)
                                }
                            }
                        }
                    }
                    .disabled(settings.isManagedByAdmin)
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
                    if settings.isManagedByAdmin {
                        Label("관리자가 시간 제한을 관리하고 있어요. 앱에서는 바꿀 수 없어요.", systemImage: "lock.fill")
                    } else if isLocked {
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
