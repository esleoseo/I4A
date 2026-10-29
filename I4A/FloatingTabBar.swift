import SwiftUI
import UIKit

/// Floating glass bottom bar in the style of Instagram's iOS app. It shrinks
/// while scrolling down through content and grows back on scroll up.
struct FloatingTabBar: View {
    let tabs: [WebTab]
    let active: WebTab?
    let collapsed: Bool
    let select: (WebTab) -> Void

    var body: some View {
        HStack(spacing: collapsed ? 2 : 4) {
            ForEach(tabs) { tab in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    select(tab)
                } label: {
                    TabIcon(tab: tab, selected: tab == active, collapsed: collapsed)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(tab == active ? .isSelected : [])
            }
        }
        .padding(.horizontal, collapsed ? 6 : 8)
        .padding(.vertical, collapsed ? 4 : 6)
        .liquidGlassCapsule()
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: collapsed)
    }
}

private struct TabIcon: View {
    let tab: WebTab
    let selected: Bool
    let collapsed: Bool

    var body: some View {
        Image(systemName: tab.icon(selected: selected))
            .font(.system(size: collapsed ? 17 : 22, weight: selected ? .semibold : .regular))
            .foregroundColor(.primary)
            .frame(width: collapsed ? 42 : 56, height: collapsed ? 34 : 46)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(selected ? 0.1 : 0))
            )
            .contentShape(Capsule())
    }
}

/// Short notice shown when a Reel was stopped from playing.
struct ReelNotice: View {
    var body: some View {
        Label("릴스는 숨겨져 있어요", systemImage: "eye.slash")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .liquidGlassCapsule()
    }
}

/// Asks the user to delete the official Instagram app; dismissible.
struct InstagramInstalledBanner: View {
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 20))
            VStack(alignment: .leading, spacing: 4) {
                Text(InstagramApp.alertTitle)
                    .font(.subheadline.weight(.bold))
                Text(InstagramApp.alertMessage)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("닫기")
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
    }
}

extension View {
    /// Liquid Glass on iOS 26; a translucent material capsule before that.
    #if compiler(>=6.2)
    @ViewBuilder
    func liquidGlassCapsule() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: Capsule())
        } else {
            materialCapsule()
        }
    }
    #else
    func liquidGlassCapsule() -> some View {
        materialCapsule()
    }
    #endif

    private func materialCapsule() -> some View {
        background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
    }
}
