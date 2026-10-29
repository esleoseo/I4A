import SwiftUI

/// Covers Instagram once today's time is used up.
struct LimitReachedView: View {
    @EnvironmentObject private var settings: AppSettings
    @Binding var showSettings: Bool

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "hourglass.bottomhalf.filled")
                .font(.system(size: 56, weight: .regular))
                .foregroundColor(.accentColor)
            Text("오늘의 인스타그램 시간을\n모두 사용했어요")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text("하루 \(TimeFormat.short(settings.dailyLimitSeconds))을 다 썼어요.\n자정이 지나면 다시 열려요.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("설정") { showSettings = true }
                .font(.subheadline)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        // Swallow every touch so nothing reaches the page underneath.
        .contentShape(Rectangle())
    }
}
