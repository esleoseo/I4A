import Foundation

/// An item of the native bottom bar. Listed in the order of Instagram's iOS
/// app bar (Home, Reels, Messages, Search, Profile). `create` is a web bar
/// item only: the app's bar has no "new post" button, so neither has ours.
enum WebTab: String, CaseIterable, Identifiable {
    case home, reels, direct, explore, profile, create

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "홈"
        case .explore: return "검색"
        case .reels: return "릴스"
        case .create: return "만들기"
        case .direct: return "메시지"
        case .profile: return "프로필"
        }
    }

    func icon(selected: Bool) -> String {
        switch self {
        case .home: return selected ? "house.fill" : "house"
        case .explore: return "magnifyingglass"
        case .reels: return selected ? "play.rectangle.fill" : "play.rectangle"
        case .create: return "plus.app"
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
        case .create: return nil
        }
    }

    /// The tab a page belongs to, for highlighting.
    static func active(forPath path: String, profilePath: String?) -> WebTab? {
        let path = path.isEmpty ? "/" : path
        if path == "/" { return .home }
        if path.hasPrefix("/explore") { return .explore }
        if path.hasPrefix("/reels") { return .reels }
        if path.hasPrefix("/direct") { return .direct }
        if let profilePath, path.lowercased().hasPrefix(profilePath.lowercased()) { return .profile }
        return nil
    }

    /// Pages where Instagram's web drops its own bar but the native one
    /// should stay so people can get around: the DM inbox and requests, not a
    /// conversation (its message box sits at the bottom).
    static func keepsBarWithoutInstagramNav(onPath path: String) -> Bool {
        path.hasPrefix("/direct/") && !path.hasPrefix("/direct/t/")
    }

    /// Pages that use the bottom of the screen themselves (message composer,
    /// story viewer, post editor, login and settings forms).
    /// The page script's NO_BAR (ContentScripts) mirrors this list.
    static func hidesBar(onPath path: String) -> Bool {
        let prefixes = ["/direct/t/", "/stories/", "/create/", "/accounts/", "/challenge/"]
        return prefixes.contains { path.hasPrefix($0) }
    }
}
