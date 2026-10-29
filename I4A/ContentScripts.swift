import WebKit

/// JavaScript/CSS injected into instagram.com.
///
/// Scripts run in an isolated content world, so Instagram's own scripts can't
/// see or tamper with them; only the DOM is shared.
enum ContentScripts {
    static let world = WKContentWorld.defaultClient
    static let messageHandlerName = "i4a"

    /// Rules match stable hooks (href, tag names), never Instagram's generated
    /// class names. `:has()` keeps applying as Instagram re-renders, so no DOM
    /// polling is needed for them. `/explore/` is excluded so hashtag links
    /// such as `/explore/tags/reel/` don't take ordinary posts down with them.
    ///
    /// - `data-i4a-reels` on <html>: Reels hiding is on.
    /// - `data-i4a-feed` on <html>: the home feed is showing.
    /// - `data-i4a-nav`: Instagram's own bottom bar, replaced by the native one.
    /// - `data-i4a-blocked`: a Reels viewer that couldn't be closed.
    static let css = """
    html[data-i4a-reels] a[href="/reels/"],
    html[data-i4a-reels] a[href="/reels"],
    html[data-i4a-reels] a[href^="/reels/"],
    html[data-i4a-reels] a[href^="/reels?"],
    html[data-i4a-reels] a[href*="instagram.com/reels"],
    html[data-i4a-reels] a[href$="/reels/"]:not([href*="/explore/"]),
    html[data-i4a-reels] a[href*="/reel/"]:not([href*="/explore/"]),
    html[data-i4a-reels] div:has(> a[href="/reels/"]:only-child),
    html[data-i4a-reels] li:has(> a[href="/reels/"]:only-child),
    html[data-i4a-reels][data-i4a-feed] article:has(a[href*="/reel/"]:not([href*="/explore/"])),
    [data-i4a-nav],
    [data-i4a-blocked] {
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

    /// Re-applies everything and reports the page state; called on every URL change.
    static let refreshJS = "window.__i4a && window.__i4a.refresh(); true;"

    /// Taps an item of Instagram's (hidden) bottom bar; evaluates to whether it was found.
    static func tapJS(_ kind: String) -> String {
        "window.__i4a ? window.__i4a.tap(\(jsStringLiteral(kind))) : false;"
    }

    static let scrollToTopJS = "window.scrollTo({ top: 0, behavior: 'smooth' }); true;"

    static func bootstrapJS(hideReels: Bool) -> String {
        """
        (function () {
          'use strict';
          var hide = \(hideReels);
          if (window.__i4a) { window.__i4a.setHideReels(hide); return; }

          var STYLE_ID = 'i4a-style';
          var CSS = \(jsStringLiteral(css));
          var RESERVED = /^\\/(explore|reels?|direct|accounts|stories|p|tv|about|legal|create|notifications|your_activity|emails|challenge|web|session|privacy|settings|developer|api|graphql|ajax)\\//;

          var nav = null;
          var items = {};
          var lastReport = '';

          function setFlag(name, on) {
            var root = document.documentElement;
            if (on !== root.hasAttribute(name)) {
              if (on) { root.setAttribute(name, ''); } else { root.removeAttribute(name); }
            }
          }

          function ensureStyle() {
            var root = document.documentElement;
            if (!root) { return false; }
            if (!document.getElementById(STYLE_ID)) {
              var el = document.createElement('style');
              el.id = STYLE_ID;
              el.textContent = CSS;
              // A direct child of <html>: the page's own code never replaces it.
              root.appendChild(el);
            }
            setFlag('data-i4a-reels', hide);
            // Feed rules only apply on the home feed; post pages also use <article>.
            setFlag('data-i4a-feed', location.pathname === '/');
            return true;
          }

          // Instagram's bottom bar: a fixed element at the bottom of the
          // viewport holding the Explore / Direct links.
          function findNav() {
            if (nav && nav.isConnected) { return nav; }
            // Already found and hidden earlier (its size is 0 now, so it can't
            // be measured again).
            nav = document.querySelector('[data-i4a-nav]');
            if (nav) { return nav; }
            var probes = document.querySelectorAll('a[href="/explore/"], a[href^="/direct/inbox"]');
            for (var i = 0; i < probes.length && !nav; i++) {
              var el = probes[i];
              for (var depth = 0; el && el !== document.body && depth < 12; depth++, el = el.parentElement) {
                var position = getComputedStyle(el).position;
                if (position !== 'fixed' && position !== 'sticky') { continue; }
                var rect = el.getBoundingClientRect();
                if (rect.height > 0 && rect.height < 160 &&
                    rect.bottom >= window.innerHeight - 8 &&
                    el.querySelectorAll('a[href]').length >= 3) {
                  nav = el;
                }
                break;
              }
            }
            if (nav) { nav.setAttribute('data-i4a-nav', ''); }
            return nav;
          }

          function kindOf(el) {
            var href = el.getAttribute('href');
            if (href === null || href === '' || href === '#') {
              return el.tagName === 'A' || !el.querySelector('a[href]') ? 'create' : null;
            }
            if (href === '/' || href.indexOf('/?') === 0) { return 'home'; }
            if (href.indexOf('/explore') === 0) { return 'explore'; }
            if (href.indexOf('/reels') === 0) { return 'reels'; }
            if (href.indexOf('/direct') === 0) { return 'direct'; }
            if (/^\\/[A-Za-z0-9._]+\\/$/.test(href) && !RESERVED.test(href)) { return 'profile'; }
            return null;
          }

          function collectNavItems() {
            items = {};
            var kinds = [];
            var profile = null;
            if (!nav) { return { kinds: kinds, profile: profile }; }
            var els = nav.querySelectorAll('a, button, [role="button"], [role="link"]');
            for (var i = 0; i < els.length; i++) {
              var kind = kindOf(els[i]);
              if (!kind || items[kind]) { continue; }
              items[kind] = els[i];
              kinds.push(kind);
              if (kind === 'profile') { profile = els[i].getAttribute('href'); }
            }
            return { kinds: kinds, profile: profile };
          }

          // Make iOS Password AutoFill and SMS code suggestions kick in.
          function setAutocomplete(selector, value) {
            var els = document.querySelectorAll(selector);
            for (var i = 0; i < els.length; i++) {
              if (els[i].getAttribute('autocomplete') !== value) {
                els[i].setAttribute('autocomplete', value);
              }
            }
          }

          function improveLogin() {
            if (location.pathname.indexOf('signup') !== -1) { return; }
            setAutocomplete('input[name="username"], input[name="email"]', 'username');
            setAutocomplete('input[name="password"], input[name="pass"]', 'current-password');
            setAutocomplete('input[name="verificationCode"], input[name="security_code"], input[name="approvals_code"]', 'one-time-code');
          }

          // A Reel shared in a DM plays in an overlay while the URL stays on
          // /direct/, so URL-based blocking never sees it. Catch any large
          // video there instead, stop it and close the overlay.
          function isBigVideo(video) {
            var rect = video.getBoundingClientRect();
            return rect.width >= window.innerWidth * 0.6 && rect.height >= window.innerHeight * 0.4;
          }

          function closeViewer(video) {
            try { video.pause(); video.muted = true; } catch (e) {}
            if (video.hasAttribute('data-i4a-handled')) { return false; }
            video.setAttribute('data-i4a-handled', '');
            var container = video.closest('[role="dialog"]');
            if (!container) {
              for (var el = video.parentElement; el && el !== document.body; el = el.parentElement) {
                if (getComputedStyle(el).position === 'fixed') { container = el; break; }
              }
            }
            if (!container) { return true; }
            var labels = container.querySelectorAll('[aria-label]');
            for (var i = 0; i < labels.length; i++) {
              if (/^(close|닫기)$/i.test(labels[i].getAttribute('aria-label').trim())) {
                (labels[i].closest('button, [role="button"], a') || labels[i]).click();
                break;
              }
            }
            // If closing didn't take it away, hide it.
            setTimeout(function () {
              if (container.isConnected) { container.setAttribute('data-i4a-blocked', ''); }
            }, 300);
            return true;
          }

          function blockDirectReels() {
            if (!hide || location.pathname.indexOf('/direct/') !== 0) { return false; }
            var videos = document.querySelectorAll('video');
            for (var i = 0; i < videos.length; i++) {
              if (isBigVideo(videos[i]) && closeViewer(videos[i])) { return true; }
            }
            return false;
          }

          document.addEventListener('play', function (event) {
            var video = event.target;
            if (hide && video && video.tagName === 'VIDEO' &&
                location.pathname.indexOf('/direct/') === 0 && isBigVideo(video) &&
                closeViewer(video)) {
              post({ blockedReel: true });
            }
          }, true);

          function post(message) {
            try { window.webkit.messageHandlers.\(messageHandlerName).postMessage(message); } catch (e) {}
          }

          function report() {
            var state = collectNavItems();
            state.nav = !!nav;
            state.login = !!document.querySelector('input[type="password"]');
            var serialized = JSON.stringify(state);
            if (serialized !== lastReport) {
              lastReport = serialized;
              post(state);
            }
          }

          function refresh() {
            if (!ensureStyle()) { return; }
            findNav();
            improveLogin();
            if (blockDirectReels()) { post({ blockedReel: true }); }
            report();
          }

          var pending = false;
          function schedule() {
            if (pending) { return; }
            pending = true;
            setTimeout(function () { pending = false; refresh(); }, 250);
          }

          window.__i4a = {
            refresh: refresh,
            setHideReels: function (value) { hide = !!value; refresh(); },
            tap: function (kind) {
              findNav();
              collectNavItems();
              var el = items[kind];
              if (!el || !el.isConnected) { return false; }
              el.click();
              return true;
            }
          };

          ensureStyle();
          new MutationObserver(schedule).observe(document, { childList: true, subtree: true });
          document.addEventListener('DOMContentLoaded', refresh);
          window.addEventListener('popstate', schedule);
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
