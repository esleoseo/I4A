import SwiftUI
import UIKit

/// Floating glass bottom bar in the style of Instagram's iOS 26 app: icons
/// spread over a wide capsule, a highlight that slides to the selected tab,
/// and a finger dragged along the bar carries the highlight with it,
/// opening the tab it is let go on. It shrinks while scrolling down through
/// content and grows back on scroll up.
struct FloatingTabBar: View {
    let tabs: [WebTab]
    let active: WebTab?
    let collapsed: Bool
    let avatarURL: URL?
    let select: (WebTab) -> Void

    /// The tab under the finger while it's on the bar.
    @State private var touchedIndex: Int?
    @Namespace private var highlight

    private var highlightedIndex: Int? {
        touchedIndex ?? active.flatMap { tabs.firstIndex(of: $0) }
    }

    var body: some View {
        GeometryReader { proxy in
            let itemWidth = proxy.size.width / CGFloat(max(tabs.count, 1))
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                    TabIcon(tab: tab, selected: tab == active, collapsed: collapsed, avatarURL: avatarURL)
                        .frame(width: itemWidth, height: proxy.size.height)
                        .background {
                            if index == highlightedIndex {
                                Capsule()
                                    .fill(Color.primary.opacity(touchedIndex == nil ? 0.1 : 0.16))
                                    .padding(.vertical, collapsed ? 3 : 5)
                                    .padding(.horizontal, 2)
                                    .scaleEffect(touchedIndex == nil ? 1 : 1.12)
                                    .matchedGeometryEffect(id: "highlight", in: highlight)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(tab.title)
                        .accessibilityAddTraits(tab == active ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { select(tab) }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let index = self.index(at: value.location.x, itemWidth: itemWidth)
                        guard index != touchedIndex else { return }
                        if touchedIndex == nil {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } else {
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                        touchedIndex = index
                    }
                    .onEnded { value in
                        let index = self.index(at: value.location.x, itemWidth: itemWidth)
                        touchedIndex = nil
                        // Let go well away from the bar: cancelled.
                        guard value.location.y > -60, value.location.y < proxy.size.height + 60,
                              tabs.indices.contains(index) else { return }
                        select(tabs[index])
                    }
            )
        }
        .frame(height: collapsed ? 46 : 60)
        .padding(.horizontal, 4)
        .liquidGlassCapsule()
        .padding(.horizontal, collapsed ? 64 : 18)
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: highlightedIndex)
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: touchedIndex == nil)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: collapsed)
    }

    private func index(at x: CGFloat, itemWidth: CGFloat) -> Int {
        guard itemWidth > 0, !tabs.isEmpty else { return 0 }
        return min(max(Int(x / itemWidth), 0), tabs.count - 1)
    }
}

private struct TabIcon: View {
    let tab: WebTab
    let selected: Bool
    let collapsed: Bool
    let avatarURL: URL?

    var body: some View {
        if tab == .profile, let avatarURL {
            let size: CGFloat = collapsed ? 22 : 27
            AsyncImage(url: avatarURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(Color.primary.opacity(0.15))
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            // Selected: a ring around the picture, as in Instagram's bar.
            .padding(2)
            .overlay(Circle().stroke(Color.primary, lineWidth: 1.5).opacity(selected ? 1 : 0))
        } else {
            Image(systemName: tab.icon(selected: selected))
                .font(.system(size: collapsed ? 19 : 23, weight: selected ? .semibold : .regular))
                .foregroundColor(.primary)
        }
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

extension View {
    /// Liquid Glass on iOS 26; a translucent material capsule before that.
    #if compiler(>=6.2)
    @ViewBuilder
    func liquidGlassCapsule() -> some View {
        if #available(iOS 26.0, *) {
            // Not `.interactive()`: its touch tracking crashed the app
            // (NSArray nil insert in gesture handling) when the web view
            // underneath was touched.
            glassEffect(.regular, in: Capsule())
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
