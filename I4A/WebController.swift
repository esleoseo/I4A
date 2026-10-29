import SwiftUI
import UIKit
import WebKit

/// Owns the single WKWebView showing Instagram and enforces the navigation rules.
final class WebController: NSObject, ObservableObject {
    /// Message for the error overlay when the page couldn't load.
    @Published private(set) var loadError: String?

    let webView: WKWebView

    private let userContentController: WKUserContentController
    private let refreshControl = UIRefreshControl()
    private var urlObservation: NSKeyValueObservation?
    private var hideReels: Bool
    private var isSuspended = false
    private var needsReload = false
    private var bounceScheduled = false
    private var failedURL: URL?

    init(hideReels: Bool) {
        self.hideReels = hideReels

        let contentController = WKUserContentController()
        contentController.addUserScript(ContentScripts.userScript(hideReels: hideReels))
        userContentController = contentController

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

        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = false
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif

        refreshControl.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl

        // Instagram is a single-page app: moving between pages uses
        // history.pushState, which never reaches the navigation delegate.
        // WKWebView still updates `url`, so watch it to catch Reels.
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
            DispatchQueue.main.async { self?.urlDidChange(webView.url) }
        }

        webView.load(URLRequest(url: NavigationPolicy.homeURL))
    }

    deinit {
        urlObservation?.invalidate()
    }

    // MARK: - Commands

    func setHideReels(_ hide: Bool) {
        guard hide != hideReels else { return }
        hideReels = hide
        userContentController.removeAllUserScripts()
        userContentController.addUserScript(ContentScripts.userScript(hideReels: hide))
        evaluate(ContentScripts.setHideReelsJS(hide))
        urlDidChange(webView.url)
    }

    /// Freezes the page while the daily limit is reached.
    func setSuspended(_ suspended: Bool) {
        guard suspended != isSuspended else { return }
        isSuspended = suspended
        webView.isUserInteractionEnabled = !suspended
        if suspended {
            webView.pauseAllMediaPlayback(completionHandler: nil)
            webView.setAllMediaPlaybackSuspended(true, completionHandler: nil)
        } else {
            webView.setAllMediaPlaybackSuspended(false, completionHandler: nil)
            if needsReload {
                needsReload = false
                reload()
            }
        }
    }

    /// The content process may have been killed while in the background,
    /// leaving a blank page.
    func appDidBecomeActive() {
        if webView.url == nil && !webView.isLoading && !isSuspended {
            reload()
        }
    }

    func retry() {
        loadError = nil
        if let failedURL {
            webView.load(URLRequest(url: failedURL))
        } else {
            reload()
        }
    }

    func reload() {
        if webView.url == nil {
            webView.load(URLRequest(url: NavigationPolicy.homeURL))
        } else {
            webView.reload()
        }
    }

    // MARK: - Private

    @objc private func pullToRefresh() {
        reload()
        // Never leave the spinner stuck if no delegate callback arrives.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.endRefreshing()
        }
    }

    private func endRefreshing() {
        if refreshControl.isRefreshing { refreshControl.endRefreshing() }
    }

    private func urlDidChange(_ url: URL?) {
        evaluate(ContentScripts.ensureJS)
        guard hideReels, NavigationPolicy.isReels(url) else { return }
        leaveReels()
    }

    /// Steps back from a Reels page, or goes home if there's nowhere to go back to.
    private func leaveReels() {
        guard !bounceScheduled else { return }
        bounceScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.bounceScheduled = false
            guard self.hideReels, NavigationPolicy.isReels(self.webView.url) else { return }
            if let back = self.webView.backForwardList.backItem,
               !NavigationPolicy.isReels(back.url) {
                self.webView.goBack()
            } else {
                self.webView.load(URLRequest(url: NavigationPolicy.homeURL))
            }
        }
    }

    private func evaluate(_ js: String) {
        webView.evaluateJavaScript(js, in: nil, in: ContentScripts.world, completionHandler: nil)
    }

    private func openExternally(_ url: URL) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    private func handle(_ error: Error, provisional: Bool) {
        endRefreshing()
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
        var top = webView.window?.rootViewController
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
        endRefreshing()
        evaluate(ContentScripts.ensureJS)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handle(error, provisional: true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handle(error, provisional: false)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // The page process crashed or was killed for memory; bring it back.
        endRefreshing()
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
        guard let presenter = presenter() else {
            completionHandler()
            return
        }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default) { _ in completionHandler() })
        presenter.present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard let presenter = presenter() else {
            completionHandler(false)
            return
        }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "취소", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "확인", style: .default) { _ in completionHandler(true) })
        presenter.present(alert, animated: true)
    }
}

// MARK: - SwiftUI bridge

struct InstagramWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
