import Foundation

enum NavigationDecision: Equatable {
    case allow
    /// A Reels page while Reels are hidden.
    case blockReels
    /// Leaves Instagram: hand it to the system (Safari, Mail, ...).
    case openExternally
    /// App deep links and store redirects; dropped silently.
    case cancel
}

enum NavigationPolicy {
    static let homeURL = URL(string: "https://www.instagram.com/")!

    /// Hosts that may load in the main frame. Facebook domains are needed for
    /// "Log in with Facebook" and account center flows.
    static let allowedHostSuffixes = [
        "instagram.com",
        "instagr.am",
        "ig.me",
        "cdninstagram.com",
        "facebook.com",
        "facebook.net",
        "fbcdn.net",
        "fbsbx.com",
        "fb.com",
    ]

    static func isAllowedHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased(), !host.isEmpty else { return false }
        return allowedHostSuffixes.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    static func isInstagramHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "instagram.com" || host.hasSuffix(".instagram.com")
    }

    /// Matches `/reels/...`, `/reel/<code>/`, `/<user>/reels/` and `/<user>/reel/<code>/`.
    static func isReels(_ url: URL?) -> Bool {
        guard let url, isInstagramHost(url.host) else { return false }
        let parts = url.path.lowercased().split(separator: "/")
        guard let first = parts.first else { return false }
        if first == "reels" || first == "reel" { return true }
        if parts.count >= 2, parts[1] == "reels" || parts[1] == "reel" { return true }
        return false
    }

    static func decide(url: URL, isMainFrame: Bool, hideReels: Bool) -> NavigationDecision {
        let scheme = url.scheme?.lowercased() ?? ""
        switch scheme {
        case "http", "https":
            // Subresources and iframes (captcha, embeds) are left alone.
            guard isMainFrame else { return .allow }
            if hideReels && isReels(url) { return .blockReels }
            return isAllowedHost(url.host) ? .allow : .openExternally
        case "about", "blob", "data":
            return .allow
        case "mailto", "tel", "sms":
            return isMainFrame ? .openExternally : .cancel
        default:
            // instagram://, itms-apps://, intent:// ... Opening the real app
            // would defeat the purpose of this one.
            return .cancel
        }
    }
}
