import SwiftUI
import UIKit
import WebKit

/// Owns the single WKWebView showing Instagram and enforces the navigation rules.
final class WebController: NSObject, ObservableObject {
    /// Message for the error overlay when the page couldn't load.
    @Published private(set) var loadError: String?
    /// Items of Instagram's own bottom bar; empty when the page has none.
    @Published private(set) var tabs: [WebTab] = []
    @Published private(set) var activeTab: WebTab?
    /// The page needs the bottom of the screen (DM thread, login form, ...).
    @Published private(set) var pageHidesBar = false
    /// The user is scrolling down through content: shrink the bar.
    @Published private(set) var isBarCollapsed = false
    /// Bumped whenever a Reel was stopped from playing, to show a notice.
    @Published private(set) var blockedReelCount = 0

    /// Created only once it can go straight into a window; see `attach(to:)`.
    private var webView: WKWebView?

    private let configuration: WKWebViewConfiguration
    private let userContentController: WKUserContentController
    private var urlObservation: NSKeyValueObservation?
    private var pageHasLoginForm = false
    private var pageHasOverlay = false
    /// Items of Instagram's own bar on the current page; nil when it has none.
    private var pageNavTabs: [WebTab]?
    /// The bar as last seen, for pages where Instagram drops it (DM inbox).
    private var lastKnownTabs: [WebTab] = []
    /// Instagram's own bar is briefly shown (its "new post" button was used).
    private var pageShowsInstagramNav = false
    private static let profilePathKey = "web.profilePath"
    private var profilePath: String? = UserDefaults.standard.string(forKey: WebController.profilePathKey) {
        didSet { UserDefaults.standard.set(profilePath, forKey: Self.profilePathKey) }
    }
    private var hideReels: Bool

    /// A Reel the user tapped in a DM. Its page may load within a short
    /// window; staying on it stays allowed, moving on to another Reel doesn't.
    private struct ReelGrant {
        let code: String
        let at: Date
        var entered = false
    }
    private var reelGrant: ReelGrant?
    private static let reelGrantWindow: TimeInterval = 15
    private var isSuspended = false
    private var needsReload = false
    private var bounceScheduled = false
    /// When the last few bounces off Reels happened, to catch a page that
    /// keeps sending us back (stepping back, it reopens the Reel, and so on).
    private var recentBounces: [Date] = []
    private var failedURL: URL?
    private var lastTermination: Date?

    init(hideReels: Bool) {
        self.hideReels = hideReels

        let contentController = WKUserContentController()
        contentController.addUserScript(ContentScripts.userScript(hideReels: hideReels))
        userContentController = contentController
        let messageProxy = MessageProxy()
        contentController.add(messageProxy, contentWorld: ContentScripts.world, name: ContentScripts.messageHandlerName)

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        // Muted autoplay works as on Safari; sound needs a tap.
        config.mediaTypesRequiringUserActionForPlayback = .audio
        // No floating video that keeps playing past the time limit.
        config.allowsPictureInPictureMediaPlayback = false
        // Look like mobile Safari so Instagram serves its regular mobile site.
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        config.applicationNameForUserAgent = "Version/\(major).0 Mobile/15E148 Safari/604.1"

        configuration = config
        super.init()
        messageProxy.target = self
    }

    /// Puts the web view into `container`, creating it the first time.
    ///
    /// Only called once the container is in a window. A web view made any
    /// earlier (this controller is created while the app is still starting,
    /// before its window exists) gets gesture recognizers without a touch
    /// dispatcher, and on iOS 26 the first touch on it crashes the app:
    /// NSArray nil insert in -[UIGestureRecognizer _delayTouchesForEvent:inPhase:].
    /// It's also made only once the container has its size: a page that
    /// starts loading in a zero-size view lays itself out for the wrong
    /// width and comes up zoomed in, cut off at the right.
    func attach(to container: UIView) {
        guard self.webView != nil || !container.bounds.isEmpty else { return }
        let webView = self.webView ?? makeWebView(frame: container.bounds)
        guard webView.superview !== container else { return }
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(webView)
    }

    private func makeWebView(frame: CGRect) -> WKWebView {
        let webView = WKWebView(frame: frame, configuration: configuration)
        self.webView = webView

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = false
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif

        // No pull-to-refresh: it shifts the whole page down, which tears
        // Instagram's fixed header away from the content. Refresh is tapping
        // Home again at the top of the feed, as in Instagram's app.
        // The view runs under the home indicator. Left to adjust for it, the
        // scroll view treats that strip as covered, and iOS 26 paints it as a
        // solid band over the page, hiding what Instagram pins to the bottom
        // (the comment box). The page fills the whole view instead.
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        // Instagram is a single-page app: moving between pages uses
        // history.pushState, which never reaches the navigation delegate.
        // WKWebView still updates `url`, so watch it to catch Reels.
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
            DispatchQueue.main.async { self?.urlDidChange(webView.url) }
        }

        // The limit may already have been reached before the page existed.
        if isSuspended { applySuspension(to: webView) }

        webView.load(URLRequest(url: NavigationPolicy.homeURL))
        return webView
    }

    deinit {
        urlObservation?.invalidate()
        userContentController.removeScriptMessageHandler(
            forName: ContentScripts.messageHandlerName, contentWorld: ContentScripts.world)
    }

    // MARK: - Commands

    func setHideReels(_ hide: Bool) {
        guard hide != hideReels else { return }
        hideReels = hide
        userContentController.removeAllUserScripts()
        userContentController.addUserScript(ContentScripts.userScript(hideReels: hide))
        evaluate(ContentScripts.setHideReelsJS(hide))
        if let webView { urlDidChange(webView.url) }
    }

    /// Freezes the page while the daily limit is reached.
    func setSuspended(_ suspended: Bool) {
        guard suspended != isSuspended else { return }
        isSuspended = suspended
        guard let webView else { return } // applied when it's created
        applySuspension(to: webView)
        if !suspended && needsReload {
            needsReload = false
            reload()
        }
    }

    private func applySuspension(to webView: WKWebView) {
        webView.isUserInteractionEnabled = !isSuspended
        if isSuspended {
            webView.pauseAllMediaPlayback(completionHandler: nil)
            webView.setAllMediaPlaybackSuspended(true, completionHandler: nil)
        } else {
            webView.setAllMediaPlaybackSuspended(false, completionHandler: nil)
        }
    }

    /// The content process may have been killed while in the background,
    /// leaving a blank page.
    func appDidBecomeActive() {
        guard let webView else { return }
        if webView.url == nil && !webView.isLoading && !isSuspended {
            reload()
        }
    }

    /// Bottom bar tap. Taps Instagram's own (hidden) bar item so the page
    /// navigates as usual.
    func select(_ tab: WebTab) {
        guard let webView else { return }
        setBarCollapsed(false)
        if tab == activeTab, tab != .create {
            // Like Instagram's app: tapping the current tab scrolls back to
            // the top; tapping Home again once there refreshes the feed.
            if tab == .home && webView.scrollView.contentOffset.y <= 1 {
                reload()
            } else {
                webView.scrollView.setContentOffset(.zero, animated: true)
                evaluate(ContentScripts.scrollToTopJS)
            }
            return
        }
        webView.evaluateJavaScript(ContentScripts.tapJS(tab.rawValue), in: nil, in: ContentScripts.world) { [weak self] result in
            guard let self else { return }
            if case .success(let value) = result, value as? Bool == true { return }
            guard let path = tab.fallbackPath(profilePath: self.profilePath),
                  let url = URL(string: path, relativeTo: NavigationPolicy.homeURL) else { return }
            webView.load(URLRequest(url: url))
        }
    }

    /// Stops audio and video, e.g. while the settings sheet covers the page.
    func pauseMedia() {
        webView?.pauseAllMediaPlayback(completionHandler: nil)
    }

    func retry() {
        loadError = nil
        lastTermination = nil
        if let failedURL {
            webView?.load(URLRequest(url: failedURL))
        } else {
            reload()
        }
    }

    func reload() {
        guard let webView else { return }
        if webView.url == nil {
            webView.load(URLRequest(url: NavigationPolicy.homeURL))
        } else {
            webView.reload()
        }
    }

    // MARK: - Private

    private func urlDidChange(_ url: URL?) {
        evaluate(ContentScripts.refreshJS)
        updatePageState()
        setBarCollapsed(false)
        if var grant = reelGrant {
            if NavigationPolicy.reelCode(url) == grant.code {
                grant.entered = true
                reelGrant = grant
            } else if grant.entered || Date().timeIntervalSince(grant.at) > Self.reelGrantWindow {
                // Left the tapped Reel (or never went): it's used up.
                reelGrant = nil
            }
        }
        guard hideReels, NavigationPolicy.isReels(url), !isGranted(url) else { return }
        leaveReels()
    }

    /// The Reel page `url` is the one the user tapped in a DM.
    private func isGranted(_ url: URL?) -> Bool {
        guard let grant = reelGrant, let code = NavigationPolicy.reelCode(url), code == grant.code else { return false }
        return grant.entered || Date().timeIntervalSince(grant.at) <= Self.reelGrantWindow
    }

    private func updatePageState() {
        let path = webView?.url.flatMap { NavigationPolicy.isInstagramHost($0.host) ? $0.path : nil } ?? ""
        let active = WebTab.active(forPath: path, profilePath: profilePath)
        if active != activeTab { activeTab = active }
        let hides = path.isEmpty || pageHasLoginForm || pageHasOverlay || pageShowsInstagramNav ||
            WebTab.hidesBar(onPath: path)
        if hides != pageHidesBar { pageHidesBar = hides }

        // Instagram's own items; on pages where it drops its bar but people
        // still need to get around (the DM inbox), the last ones seen. "New
        // post" needs Instagram's own button, so it's left out there.
        var shown: [WebTab] = []
        if let navTabs = pageNavTabs {
            shown = navTabs
        } else if WebTab.keepsBarWithoutInstagramNav(onPath: path) {
            let known = lastKnownTabs.isEmpty ? [.home, .explore, .direct, .profile] : lastKnownTabs
            shown = known.filter { $0 != .create && ($0 != .profile || profilePath != nil) }
        }
        shown.removeAll { hideReels && $0 == .reels }
        if shown != tabs { tabs = shown }
    }

    fileprivate func receive(_ body: Any) {
        guard let message = body as? [String: Any] else { return }
        if message["blockedReel"] as? Bool == true {
            blockedReelCount += 1
            return
        }
        if let collapsed = message["barCollapsed"] as? Bool {
            // Scroll direction, reported by the page (see ContentScripts).
            setBarCollapsed(collapsed)
            return
        }
        if let code = message["grantReel"] as? String {
            // Sent when the user taps a Reel in a DM conversation.
            if NavigationPolicy.isValidReelCode(code) { reelGrant = ReelGrant(code: code, at: Date()) }
            return
        }
        if let path = message["profile"] as? String, path.hasPrefix("/"), path != profilePath {
            profilePath = path
        }
        let hasNav = message["nav"] as? Bool ?? false
        let kinds = (message["kinds"] as? [String] ?? []).compactMap(WebTab.init(rawValue:))
        let order = WebTab.allCases.filter { kinds.contains($0) }
        pageNavTabs = hasNav ? order : nil
        if hasNav && !order.isEmpty { lastKnownTabs = order }
        pageHasLoginForm = message["login"] as? Bool ?? false
        pageHasOverlay = message["overlay"] as? Bool ?? false
        pageShowsInstagramNav = message["navShown"] as? Bool ?? false
        updatePageState()
    }

    private func setBarCollapsed(_ collapsed: Bool) {
        if collapsed != isBarCollapsed { isBarCollapsed = collapsed }
    }

    /// Steps back past Reels pages, or goes home if there's nowhere to go back to.
    private func leaveReels() {
        guard !bounceScheduled else { return }
        bounceScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self, let webView = self.webView else { return }
            self.bounceScheduled = false
            guard self.hideReels, NavigationPolicy.isReels(webView.url),
                  !self.isGranted(webView.url) else { return }
            let now = Date()
            self.recentBounces = self.recentBounces.filter { now.timeIntervalSince($0) < 3 } + [now]
            if self.recentBounces.count >= 3 {
                // Stepping back keeps landing on Reels: start over from home
                // with a fresh page, which also resets the page's own state.
                self.recentBounces.removeAll()
                webView.load(URLRequest(url: NavigationPolicy.homeURL))
                return
            }
            // The nearest earlier page that isn't a Reel, e.g. the DM a tapped
            // Reel was opened from when the user swipes on to the next one.
            if let back = webView.backForwardList.backList.last(where: { !NavigationPolicy.isReels($0.url) }) {
                webView.go(to: back)
            } else {
                webView.load(URLRequest(url: NavigationPolicy.homeURL))
            }
        }
    }

    private func evaluate(_ js: String) {
        webView?.evaluateJavaScript(js, in: nil, in: ContentScripts.world, completionHandler: nil)
    }

    private func openExternally(_ url: URL) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    private func handle(_ error: Error, provisional: Bool) {
        let nsError = error as NSError
        // Cancelled loads (including ones our own policy cancelled) aren't failures.
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == WKError.errorDomain && nsError.code == 102 { return } // Frame load interrupted
        guard provisional, nsError.domain == NSURLErrorDomain else { return }
        failedURL = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL
        loadError = "인스타그램을 불러오지 못했어요.\n인터넷 연결을 확인해 주세요."
    }

    /// The view controller currently on top, for presenting JavaScript dialogs.
    private func presenter() -> UIViewController? {
        var top = webView?.window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

// MARK: - WKNavigationDelegate

extension WebController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        switch NavigationPolicy.decide(url: url, isMainFrame: isMainFrame, hideReels: hideReels) {
        case .allow:
            // A tapped link to another domain (e.g. facebook.com -> instagram.com)
            // may be handed to the installed Instagram app as a universal link.
            // Programmatic loads never are, so reissue it ourselves.
            if isMainFrame,
               navigationAction.navigationType == .linkActivated,
               url.host?.lowercased() != webView.url?.host?.lowercased(),
               url.scheme?.lowercased().hasPrefix("http") == true {
                decisionHandler(.cancel)
                webView.load(navigationAction.request)
                return
            }
            decisionHandler(.allow)
        case .blockReels where isGranted(url):
            decisionHandler(.allow)
        case .blockReels:
            decisionHandler(.cancel)
            // Opened straight onto a Reel (e.g. first load): show the feed instead.
            if webView.url == nil {
                webView.load(URLRequest(url: NavigationPolicy.homeURL))
            }
        case .openExternally:
            decisionHandler(.cancel)
            openExternally(url)
        case .cancel:
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        loadError = nil
        failedURL = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        evaluate(ContentScripts.refreshJS)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handle(error, provisional: true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handle(error, provisional: false)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // The page process crashed or was killed for memory; bring it back,
        // unless it keeps dying, in which case let the user retry by hand.
        let now = Date()
        defer { lastTermination = now }
        if let last = lastTermination, now.timeIntervalSince(last) < 15 {
            failedURL = webView.url
            loadError = "페이지가 예기치 않게 종료됐어요."
            return
        }
        if isSuspended {
            needsReload = true
        } else {
            reload()
        }
    }
}

// MARK: - WKUIDelegate

extension WebController: WKUIDelegate {
    /// `target="_blank"` links and `window.open`: keep Instagram in this view,
    /// send everything else outside.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url,
              let scheme = url.scheme?.lowercased() else { return nil }
        switch NavigationPolicy.decide(url: url, isMainFrame: true, hideReels: hideReels) {
        case .allow where scheme == "http" || scheme == "https":
            webView.load(navigationAction.request)
        case .openExternally:
            openExternally(url)
        default:
            break
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let reply = DialogReply(fallback: ()) { _ in completionHandler() }
        guard !isSuspended, let presenter = presenter() else {
            reply.send(())
            return
        }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default) { _ in reply.send(()) })
        presenter.present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let reply = DialogReply(fallback: false, completionHandler)
        guard !isSuspended, let presenter = presenter() else {
            reply.send(false)
            return
        }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "취소", style: .cancel) { _ in reply.send(false) })
        alert.addAction(UIAlertAction(title: "확인", style: .default) { _ in reply.send(true) })
        presenter.present(alert, animated: true)
    }
}

/// Calls a WebKit dialog completion handler exactly once. If the alert never
/// shows (UIKit refuses a presentation mid-transition) and is released, the
/// fallback answer is sent; WebKit raises an exception for a handler that is
/// dropped without being called.
private final class DialogReply<Value> {
    private var handler: ((Value) -> Void)?
    private let fallback: Value

    init(fallback: Value, _ handler: @escaping (Value) -> Void) {
        self.fallback = fallback
        self.handler = handler
    }

    func send(_ value: Value) {
        let handler = self.handler
        self.handler = nil
        handler?(value)
    }

    deinit {
        send(fallback)
    }
}

// MARK: - Script messages

/// WKUserContentController retains its handlers; this proxy keeps that from
/// becoming a retain cycle with WebController.
private final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: WebController?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.receive(message.body)
    }
}

// MARK: - SwiftUI bridge

/// Shows the web view. It's created (and moved in) only when the container
/// is in a window and has its size; see `WebController.attach(to:)`.
struct InstagramWebView: UIViewRepresentable {
    let controller: WebController

    func makeUIView(context: Context) -> WebViewContainer {
        let container = WebViewContainer()
        container.backgroundColor = .clear
        container.controller = controller
        return container
    }

    func updateUIView(_ container: WebViewContainer, context: Context) {
        container.controller = controller
        container.attachIfInWindow()
    }
}

final class WebViewContainer: UIView {
    weak var controller: WebController?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attachIfInWindow()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        attachIfInWindow()
    }

    func attachIfInWindow() {
        guard window != nil else { return }
        controller?.attach(to: self)
    }
}
