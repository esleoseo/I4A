import WebKit

/// JavaScript/CSS injected into instagram.com.
///
/// Scripts run in an isolated content world, so Instagram's own scripts can't
/// see or tamper with them; only the DOM is shared.
enum ContentScripts {
    static let world = WKContentWorld.defaultClient

    /// Hides links to Reels everywhere, and Reels posts in the home feed.
    /// Rules match stable hooks (href, tag names), never Instagram's generated
    /// class names. `:has()` keeps applying as Instagram re-renders, so no DOM
    /// polling is needed. `/explore/` is excluded so hashtag links such as
    /// `/explore/tags/reel/` don't take ordinary posts down with them.
    static let hideReelsCSS = """
    a[href="/reels/"],
    a[href="/reels"],
    a[href^="/reels/"],
    a[href^="/reels?"],
    a[href*="instagram.com/reels"],
    a[href$="/reels/"]:not([href*="/explore/"]),
    a[href*="/reel/"]:not([href*="/explore/"]),
    div:has(> a[href="/reels/"]:only-child),
    li:has(> a[href="/reels/"]:only-child),
    html[data-i4a-feed] article:has(a[href*="/reel/"]:not([href*="/explore/"])) {
        display: none !important;
    }
    """

    static func userScript(hideReels: Bool) -> WKUserScript {
        WKUserScript(
            source: bootstrapJS(hideReels: hideReels),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: world
        )
    }

    static func setHideReelsJS(_ hide: Bool) -> String {
        "window.__i4a && window.__i4a.setHideReels(\(hide)); true;"
    }

    /// Re-checks the style and the current route; called on every URL change.
    static let ensureJS = "window.__i4a && window.__i4a.ensure(); true;"

    static func bootstrapJS(hideReels: Bool) -> String {
        """
        (function () {
          'use strict';
          var hide = \(hideReels);
          if (window.__i4a) { window.__i4a.setHideReels(hide); return; }

          var STYLE_ID = 'i4a-hide-reels';
          var CSS = \(jsStringLiteral(hideReelsCSS));

          function ensure() {
            var root = document.documentElement;
            if (!root) { return; }
            var el = document.getElementById(STYLE_ID);
            if (!el) {
              el = document.createElement('style');
              el.id = STYLE_ID;
              el.textContent = CSS;
              // A direct child of <html>: the page's own code never replaces it.
              root.appendChild(el);
            }
            var media = hide ? 'all' : 'not all';
            if (el.media !== media) { el.media = media; }
            // Feed rules only apply on the home feed; post pages also use <article>.
            var onFeed = location.pathname === '/';
            if (onFeed !== root.hasAttribute('data-i4a-feed')) {
              if (onFeed) { root.setAttribute('data-i4a-feed', ''); }
              else { root.removeAttribute('data-i4a-feed'); }
            }
          }

          window.__i4a = {
            ensure: ensure,
            setHideReels: function (value) { hide = !!value; ensure(); }
          };

          ensure();
          // WebKit runs document-start scripts once <html> exists; the check is
          // only a null guard.
          if (document.documentElement) {
            new MutationObserver(function () {
              if (!document.getElementById(STYLE_ID)) { ensure(); }
            }).observe(document.documentElement, { childList: true });
          }
          document.addEventListener('DOMContentLoaded', ensure);
          window.addEventListener('popstate', ensure);
        })();
        true;
        """
    }

    /// Encodes `string` as a JavaScript string literal.
    static func jsStringLiteral(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [string]),
              let json = String(data: data, encoding: .utf8) else { return "''" }
        // Strip the surrounding array brackets.
        return String(json.dropFirst().dropLast())
    }
}
