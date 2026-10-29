import Foundation

/// An item of the native bottom bar. Listed in the order of Instagram's iOS
/// app bar (Home, Reels, Messages, Search, Profile), which has no "new
/// post" button.
enum WebTab: String, CaseIterable, Identifiable {
    case home, reels, direct, explore, profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "홈"
        case .explore: return "검색"
        case .reels: return "릴스"
        case .direct: return "메시지"
        case .profile: return "프로필"
        }
    }

    func icon(selected: Bool) -> String {
        switch self {
        case .home: return selected ? "house.fill" : "house"
        case .explore: return "magnifyingglass"
        case .reels: return selected ? "play.rectangle.fill" : "play.rectangle"
        case .direct: return selected ? "paperplane.fill" : "paperplane"
        case .profile: return selected ? "person.crop.circle.fill" : "person.crop.circle"
        }
    }

    /// Where to go when Instagram's own bar item can't be found.
    func fallbackPath(profilePath: String?) -> String? {
        switch self {
        case .home: return "/"
        case .explore: return "/explore/"
        case .reels: return "/reels/"
        case .direct: return "/direct/inbox/"
        case .profile: return profilePath
        }
    }

    /// The tab a page belongs to, for highlighting.
    static func active(forPath path: String, profilePath: String?) -> WebTab? {
        let path = path.hasSuffix("/") ? path : path + "/"
        if path == "/" { return .home }
        if path.hasPrefix("/explore") { return .explore }
        if path.hasPrefix("/reels") { return .reels }
        if path.hasPrefix("/direct") { return .direct }
        if let profilePath, path.lowercased().hasPrefix(profilePath.lowercased()) { return .profile }
        return nil
    }

    /// Pages that use the bottom of the screen themselves (message composer,
    /// story viewer, post editor, login and settings forms, a post's
    /// comments with their comment box).
    /// The page script's NO_BAR (ContentScripts) mirrors the prefixes.
    static func hidesBar(onPath path: String) -> Bool {
        let prefixes = ["/direct/t/", "/stories/", "/create/", "/accounts/", "/challenge/"]
        return prefixes.contains { path.hasPrefix($0) } || path.hasSuffix("/comments/") || path.hasSuffix("/comments")
    }
}
