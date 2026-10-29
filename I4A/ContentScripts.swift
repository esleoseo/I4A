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
    /// - `data-i4a-blocked`: a Reel's <video>, kept hidden and paused.
    /// - `data-i4a-dm-allowed` on <html>: a 1:1 DM with an allowed account;
    ///   the Reels shared there stay visible and can be opened one at a time.
    static let css = """
    html[data-i4a-reels] a[href="/reels/"],
    html[data-i4a-reels] a[href="/reels"],
    html[data-i4a-reels] a[href^="/reels/"],
    html[data-i4a-reels] a[href^="/reels?"],
    html[data-i4a-reels] a[href*="instagram.com/reels"],
    html[data-i4a-reels] a[href$="/reels/"]:not([href*="/explore/"]),
    html[data-i4a-reels]:not([data-i4a-dm-allowed]) a[href*="/reel/"]:not([href*="/explore/"]),
    html[data-i4a-reels] div:has(> a[href="/reels/"]:only-child),
    html[data-i4a-reels] li:has(> a[href="/reels/"]:only-child),
    html[data-i4a-reels][data-i4a-feed] article:has(a[href*="/reel/"]:not([href*="/explore/"])),
    [data-i4a-nav] {
        display: none !important;
    }
    html[data-i4a-reels] video[data-i4a-blocked] {
        visibility: hidden !important;
    }
    """

    /// What the page script needs to know from the app.
    struct PageConfig: Equatable {
        var hideReels: Bool
        /// Usernames whose 1:1 DMs may show the Reels they send, one per tap.
        var dmReelAllowlist: [String]
        /// The user's own profile path ("/name/"), to tell them apart from
        /// the other person in a DM.
        var ownProfile: String?

        var json: String {
            let object: [String: Any] = [
                "hide": hideReels,
                "allow": dmReelAllowlist,
                "me": ownProfile.map { $0 as Any } ?? NSNull(),
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: object),
                  let json = String(data: data, encoding: .utf8) else { return "{}" }
            return json
        }
    }

    static func userScript(_ config: PageConfig) -> WKUserScript {
        WKUserScript(
            source: bootstrapJS(config),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: world
        )
    }

    static func configureJS(_ config: PageConfig) -> String {
        "window.__i4a && window.__i4a.configure(\(config.json)); true;"
    }

    /// Re-applies everything and reports the page state; called on every URL change.
    static let refreshJS = "window.__i4a && window.__i4a.refresh(); true;"

    /// Taps an item of Instagram's (hidden) bottom bar; evaluates to whether it was found.
    static func tapJS(_ kind: String) -> String {
        "window.__i4a ? window.__i4a.tap(\(jsStringLiteral(kind))) : false;"
    }

    static let scrollToTopJS = "window.scrollTo({ top: 0, behavior: 'smooth' }); true;"

    static func bootstrapJS(_ config: PageConfig) -> String {
        """
        (function () {
          'use strict';
          var config = \(config.json);
          if (window.__i4a) { window.__i4a.configure(config); return; }
          var hide = !!config.hide;
          var allow = config.allow || [];
          var me = config.me || null;

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
            setFlag('data-i4a-dm-allowed', inAllowedThread());
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
          // /direct/, so URL-based blocking never sees it.
          // 1) Taps on Reel links there are cancelled before Instagram sees them.
          // 2) Backstop: a large video playing in a DM, a dialog, or on a Reel
          //    post page is hidden, muted and paused, again whenever it
          //    resumes. Only the <video> is hidden, never its container, so
          //    the conversation itself can't disappear.
          // Exception: in a 1:1 DM with an allowed account, a tap lets exactly
          // one Reel play. Moving on to another Reel is blocked again.
          var lastNotice = 0;
          var tapAt = 0;
          var grant = null;
          var grantedCode = null;
          var TAP_WINDOW = 8000;
          // True while this script clicks something itself, so those clicks
          // never count as the user's tap.
          var selfClick = false;

          function clickAs(el) {
            selfClick = true;
            try { el.click(); } finally { selfClick = false; }
          }

          function notice() {
            var now = Date.now();
            if (now - lastNotice > 4000) { lastNotice = now; post({ blockedReel: true }); }
          }

          // The other person of a 1:1 thread: the single profile linked from
          // the thread header. Group threads link no single profile, so they
          // (and anything unrecognised) are never allowed.
          function threadPartner() {
            if (!/^\\/direct\\/t\\//.test(location.pathname)) { return null; }
            var names = {};
            var count = 0;
            var links = document.querySelectorAll('a[href]');
            for (var i = 0; i < links.length; i++) {
              var href = links[i].getAttribute('href');
              var match = /^\\/([A-Za-z0-9._]+)\\/?$/.exec(href);
              if (!match || RESERVED.test(href + '/')) { continue; }
              var name = match[1].toLowerCase();
              if (me && me.toLowerCase() === '/' + name + '/') { continue; }
              var rect = links[i].getBoundingClientRect();
              if (rect.height === 0 || rect.top > 140) { continue; }
              if (!names[name]) { names[name] = true; count++; }
            }
            if (count !== 1) { return null; }
            for (var key in names) { return key; }
            return null;
          }

          function inAllowedThread() {
            if (!hide || !allow.length) { return false; }
            var partner = threadPartner();
            return !!partner && allow.indexOf(partner) !== -1;
          }

          function srcOf(video) { return video.currentSrc || video.src || ''; }

          // A Reel may play only right after a tap in an allowed thread, and
          // only while it stays the same video and source.
          function isGranted(video) {
            if (tapAt && Date.now() - tapAt < TAP_WINDOW && inAllowedThread()) {
              tapAt = 0;
              grant = { video: video, src: srcOf(video) };
              video.removeAttribute('data-i4a-blocked');
              return true;
            }
            // The tapped Reel opened as its own page (/reel/CODE/, /p/CODE/).
            if (grantedCode && location.pathname.indexOf('/' + grantedCode + '/') !== -1) { return true; }
            return !!grant && grant.video === video && grant.src === srcOf(video) &&
              location.pathname.indexOf('/direct/') === 0;
          }

          function reelCode(href) {
            var match = /\\/reels?\\/([A-Za-z0-9_-]+)/.exec(href || '');
            return match && match[1] !== 'audio' ? match[1] : null;
          }

          function isReelPlayer(video) {
            if (!hide) { return false; }
            var path = location.pathname;
            if (path.indexOf('/stories/') === 0) { return false; }
            var inContext = path.indexOf('/direct/') === 0 ||
              !!video.closest('[role="dialog"], [aria-modal="true"]');
            if (!inContext && /^\\/p\\//.test(path)) {
              var link = document.querySelector('link[rel="canonical"], meta[property="og:url"]');
              var url = link ? (link.getAttribute('href') || link.getAttribute('content') || '') : '';
              inContext = url.indexOf('/reel/') !== -1;
            }
            if (!inContext) { return false; }
            // Full-width players only; inline video messages are smaller.
            var rect = video.getBoundingClientRect();
            return rect.width >= window.innerWidth * 0.85 && rect.height >= window.innerHeight * 0.5;
          }

          function closeDialog(video) {
            var dialog = video.closest('[role="dialog"], [aria-modal="true"]');
            if (!dialog) { return; }
            var labels = dialog.querySelectorAll('[aria-label]');
            for (var i = 0; i < labels.length; i++) {
              if (/^(close|닫기)$/i.test((labels[i].getAttribute('aria-label') || '').trim())) {
                clickAs(labels[i].closest('button, [role="button"], a') || labels[i]);
                return;
              }
            }
          }

          function stopReel(video) {
            var first = !video.hasAttribute('data-i4a-blocked');
            video.setAttribute('data-i4a-blocked', '');
            // Pausing inside Instagram's own play() call makes its player
            // show an error; let that call finish first.
            setTimeout(function () {
              try { video.muted = true; video.pause(); } catch (e) {}
            }, 0);
            if (first) { closeDialog(video); }
            notice();
          }

          function onMedia(event) {
            var video = event.target;
            if (!video || video.tagName !== 'VIDEO' || video.paused) { return; }
            var reel = (hide && video.hasAttribute('data-i4a-blocked')) || isReelPlayer(video);
            if (reel && !isGranted(video)) { stopReel(video); }
          }
          document.addEventListener('playing', onMedia, true);
          document.addEventListener('timeupdate', onMedia, true);

          document.addEventListener('click', function (event) {
            if (selfClick || !hide || location.pathname.indexOf('/direct/') !== 0 || !event.target.closest) { return; }
            var link = event.target.closest('a[href*="/reel/"], a[href*="/reels/"]');
            if (inAllowedThread()) {
              // Opens one Reel: the overlay player, or a Reel page the app
              // lets through for this code only.
              tapAt = Date.now();
              var code = link && reelCode(link.getAttribute('href'));
              if (code) {
                grantedCode = code;
                post({ grantReel: code });
              }
              return;
            }
            if (link) {
              event.preventDefault();
              event.stopPropagation();
              notice();
            }
          }, true);

          // Lets videos go again once they're no longer a Reel player (Reels
          // switched off, or the element reused for something else).
          function releaseVideos() {
            var blocked = document.querySelectorAll('video[data-i4a-blocked]');
            for (var i = 0; i < blocked.length; i++) {
              if (!isReelPlayer(blocked[i])) { blocked[i].removeAttribute('data-i4a-blocked'); }
            }
            var inDirect = location.pathname.indexOf('/direct/') === 0;
            if (grant && (!grant.video.isConnected || !inDirect)) { grant = null; }
            if (grantedCode && !inDirect && location.pathname.indexOf('/' + grantedCode + '/') === -1) {
              grantedCode = null;
            }
          }

          function hasOverlay() {
            var dialogs = document.querySelectorAll('[role="dialog"], [aria-modal="true"]');
            for (var i = 0; i < dialogs.length; i++) {
              if (nav && nav.contains(dialogs[i])) { continue; }
              var rect = dialogs[i].getBoundingClientRect();
              if (rect.width > 0 && rect.height > 0 && getComputedStyle(dialogs[i]).visibility !== 'hidden') { return true; }
            }
            return false;
          }

          function post(message) {
            try { window.webkit.messageHandlers.\(messageHandlerName).postMessage(message); } catch (e) {}
          }

          function report() {
            var state = collectNavItems();
            state.nav = !!nav;
            state.login = !!document.querySelector('input[type="password"]');
            // Instagram's sheets and viewers sit where the native bar is.
            state.overlay = hasOverlay();
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
            releaseVideos();
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
            configure: function (value) {
              hide = !!value.hide;
              allow = value.allow || [];
              me = value.me || null;
              refresh();
            },
            tap: function (kind) {
              findNav();
              collectNavItems();
              var el = items[kind];
              if (!el || !el.isConnected) { return false; }
              clickAs(el);
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
