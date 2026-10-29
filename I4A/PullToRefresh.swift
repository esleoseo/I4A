import UIKit

/// Pull-to-refresh as in Instagram's app: the page's header stays put, a
/// spinner shows in the gap that opens under it, and letting go once it
/// spins reloads the page.
///
/// Not UIRefreshControl: it insets the whole scroll view while refreshing,
/// which drags Instagram's fixed header away from the page.
final class PullToRefresh: NSObject {
    static let threshold: CGFloat = 70

    /// Bottom of the page's own fixed header, where the gap opens.
    var headerBottom: CGFloat = 0
    private(set) var isRefreshing = false

    private let spinner = UIActivityIndicatorView(style: .medium)
    private weak var scrollView: UIScrollView?
    private var offsetObservation: NSKeyValueObservation?
    private var armed = false
    private var timeout: DispatchWorkItem?
    private let action: () -> Void

    init(scrollView: UIScrollView, action: @escaping () -> Void) {
        self.scrollView = scrollView
        self.action = action
        super.init()
        spinner.hidesWhenStopped = false
        spinner.isUserInteractionEnabled = false
        spinner.alpha = 0
        scrollView.panGestureRecognizer.addTarget(self, action: #selector(panChanged(_:)))
        offsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
            self?.offsetChanged(scrollView)
        }
    }

    deinit {
        offsetObservation?.invalidate()
        scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(panChanged(_:)))
    }

    /// Puts the spinner over `view`, the web view's container, above the page.
    func install(in view: UIView) {
        if spinner.superview === view {
            view.bringSubviewToFront(spinner)
        } else {
            view.addSubview(spinner)
        }
    }

    /// The page finished (or failed) loading.
    func end() {
        guard isRefreshing else { return }
        isRefreshing = false
        timeout?.cancel()
        UIView.animate(withDuration: 0.2, animations: { self.spinner.alpha = 0 }, completion: { _ in
            if !self.isRefreshing && !self.armed { self.spinner.stopAnimating() }
        })
    }

    private func offsetChanged(_ scrollView: UIScrollView) {
        guard !isRefreshing else { return }
        let pull = -scrollView.contentOffset.y
        guard pull > 0 || spinner.alpha > 0 else { return }
        spinner.alpha = min(max((pull - 12) / (Self.threshold - 12), 0), 1)
        place(atY: headerBottom + max(pull, 0) / 2)
        guard scrollView.isDragging else { return }
        if pull >= Self.threshold, !armed {
            armed = true
            spinner.startAnimating()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } else if pull < Self.threshold, armed {
            armed = false
            spinner.stopAnimating()
        }
    }

    @objc private func panChanged(_ pan: UIPanGestureRecognizer) {
        guard pan.state == .ended || pan.state == .cancelled || pan.state == .failed else { return }
        guard armed else { return }
        armed = false
        if pan.state == .ended { begin() } else { spinner.stopAnimating() }
    }

    private func begin() {
        isRefreshing = true
        spinner.startAnimating()
        UIView.animate(withDuration: 0.2) {
            self.spinner.alpha = 1
            self.place(atY: self.headerBottom + 28)
        }
        // Never spin forever if no load event comes back.
        let timeout = DispatchWorkItem { [weak self] in self?.end() }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
        action()
    }

    private func place(atY y: CGFloat) {
        guard let superview = spinner.superview else { return }
        spinner.center = CGPoint(x: superview.bounds.midX, y: y)
    }
}

extension UIColor {
    /// Parses a computed CSS color, "rgb(r, g, b)" or "rgba(r, g, b, a)";
    /// nil for anything else or a see-through color.
    convenience init?(cssColor: String) {
        guard let open = cssColor.firstIndex(of: "("), let close = cssColor.lastIndex(of: ")") else { return nil }
        let parts = cssColor[cssColor.index(after: open)..<close]
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
            .compactMap { Double($0) }
        guard parts.count >= 3, (parts.count == 3 || parts[3] >= 1) else { return nil }
        self.init(red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255, alpha: 1)
    }
}
