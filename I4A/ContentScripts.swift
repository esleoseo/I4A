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
    /// - `data-i4a-show-nav` on <html>: Instagram's bar is shown for a moment
    ///   (its "new post" button was used; what it opens is anchored to it).
    /// - `data-i4a-blocked`: a Reel's <video>, kept hidden and paused.
    /// - `data-i4a-reel-tile`: an Explore grid tile that is a Reel although
    ///   it links to `/p/`. Hidden but kept in place, so the grid doesn't move.
    /// - `data-i4a-dm` on <html>: a DM conversation; the Reels shared there
    ///   stay visible and can be opened one at a time.
    static let css = """
    html[data-i4a-reels] a[href="/reels/"],
    html[data-i4a-reels] a[href="/reels"],
    html[data-i4a-reels] a[href^="/reels/"],
    html[data-i4a-reels] a[href^="/reels?"],
    html[data-i4a-reels] a[href*="instagram.com/reels"],
    html[data-i4a-reels] a[href$="/reels/"]:not([href*="/explore/"]),
    html[data-i4a-reels]:not([data-i4a-dm]) a[href*="/reel/"]:not([href*="/explore/"]),
    html[data-i4a-reels] div:has(> a[href="/reels/"]:only-child),
    html[data-i4a-reels] li:has(> a[href="/reels/"]:only-child),
    html[data-i4a-reels][data-i4a-feed] article:has(a[href*="/reel/"]:not([href*="/explore/"])),
    html:not([data-i4a-show-nav]) [data-i4a-nav] {
        display: none !important;
    }
    html[data-i4a-reels] video[data-i4a-blocked] {
        visibility: hidden !important;
    }
    html[data-i4a-reels] a[data-i4a-reel-tile] {
        visibility: hidden !important;
        pointer-events: none !important;
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
          // Pages where the app hides its bar whatever the page shows
          // (WebTab.hidesBar); keep the two in step.
          var NO_BAR = /^\\/(direct\\/t|stories|create|accounts|challenge)\\//;
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
            setFlag('data-i4a-dm', inDMThread());
            return true;
          }

          // Instagram's bottom bar: a fixed element at the bottom of the
          // viewport holding the Explore / Direct links.
          //
          // Hiding the wrong element would hide the page itself, so a
          // candidate (and the element already hidden, checked again on every
          // refresh) must look like a bar and nothing more: a handful of
          // links, and none of the page's content. While a page is still
          // loading, its whole fixed frame can briefly be as small as the bar;
          // once content arrives inside, the check fails and it's shown again.
          // The page (path) where replacing the bar was given up; see
          // guardBlankPage. Pages after it get their own try.
          var navDisabledPath = null;

          function looksLikeNav(el) {
            if (!el || !el.isConnected) { return false; }
            if (el.querySelector('main, article, textarea, input:not([type="file"]):not([type="hidden"]), video, [role="main"], [role="feed"], [role="dialog"], [contenteditable="true"]')) { return false; }
            var links = el.querySelectorAll('a[href]').length;
            return links >= 3 && links <= 12;
          }

          function unmarkNav() {
            var marked = document.querySelectorAll('[data-i4a-nav]');
            for (var i = 0; i < marked.length; i++) { marked[i].removeAttribute('data-i4a-nav'); }
            nav = null;
          }

          function findNav() {
            if (navDisabledPath === location.pathname) { return null; }
            if (nav && looksLikeNav(nav)) { return nav; }
            // Already found and hidden earlier (its size is 0 now, so it can't
            // be measured again; only its contents are checked).
            var marked = document.querySelectorAll('[data-i4a-nav]');
            nav = null;
            for (var m = 0; m < marked.length; m++) {
              if (!nav && looksLikeNav(marked[m])) { nav = marked[m]; } else { marked[m].removeAttribute('data-i4a-nav'); }
            }
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
                    rect.width >= window.innerWidth * 0.6 &&
                    looksLikeNav(el)) {
                  nav = el;
                }
                break;
              }
            }
            if (nav) { nav.setAttribute('data-i4a-nav', ''); }
            return nav;
          }

          // Last line of defence: if the middle of the page is empty with the
          // bar hidden but the "bar" covers it once shown, what was hidden is
          // the page itself. Then stop replacing the bar for this page, so
          // Instagram's own UI is back. (refresh runs this right after
          // findNav, so a wrongly hidden page isn't painted in between.)
          function guardBlankPage() {
            if (!nav) { return; }
            var x = window.innerWidth / 2, y = window.innerHeight / 2;
            var hit = document.elementFromPoint(x, y);
            if (hit && hit !== document.documentElement && hit !== document.body) { return; }
            nav.removeAttribute('data-i4a-nav');
            var shown = document.elementFromPoint(x, y);
            if (shown && nav.contains(shown)) {
              nav = null;
              navDisabledPath = location.pathname;
            } else {
              nav.setAttribute('data-i4a-nav', '');
            }
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

          // Reels shared in a DM conversation may be watched, one per tap:
          // after a tap there, the first Reel that starts playing is let
          // through. Anything else that plays as a Reel is hidden, muted and
          // paused, again whenever it resumes: swiping on to the next Reel
          // (a new source in the same player, or another player), a Reel page
          // other than the tapped one, or a Reel in a dialog elsewhere.
          // Only the <video> is hidden, never its container, so the
          // conversation itself can't disappear.
          var lastNotice = 0;
          var tapAt = 0;
          var TAP_WINDOW = 8000;
          // The Reel currently allowed to play: { video, src }.
          var grant = null;
          // The tapped Reel's code, when it opens as its own page.
          var grantedCode = null;
          var pageGranted = false;
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

          function inDMThread() {
            return hide && /^\\/direct\\/t\\//.test(location.pathname);
          }

          function onGrantedPage() {
            return !!grantedCode && location.pathname.indexOf('/' + grantedCode + '/') !== -1;
          }

          function srcOf(video) { return video.currentSrc || video.src || ''; }

          function isGranted(video) {
            if (grant && grant.video === video && grant.src === srcOf(video)) { return true; }
            var tapped = tapAt && Date.now() - tapAt < TAP_WINDOW && inDMThread();
            var firstOnPage = onGrantedPage() && !pageGranted;
            if (!tapped && !firstOnPage) { return false; }
            tapAt = 0;
            if (firstOnPage) { pageGranted = true; }
            grant = { video: video, src: srcOf(video) };
            video.removeAttribute('data-i4a-blocked');
            return true;
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
              /\\/reels?\\/[A-Za-z0-9_-]+/.test(path) ||
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
            // The Reel let through keeps firing timeupdate while it plays;
            // it needn't be measured again each time.
            if (grant && grant.video === video && grant.src === srcOf(video)) { return; }
            var reel = (hide && video.hasAttribute('data-i4a-blocked')) || isReelPlayer(video);
            if (reel && !isGranted(video)) { stopReel(video); }
          }
          document.addEventListener('playing', onMedia, true);
          document.addEventListener('timeupdate', onMedia, true);

          document.addEventListener('click', function (event) {
            if (selfClick || !hide || location.pathname.indexOf('/direct/') !== 0 || !event.target.closest) { return; }
            var link = event.target.closest('a[href*="/reel/"], a[href*="/reels/"]');
            if (inDMThread()) {
              // Opens one Reel: in the overlay player, or as its own page,
              // which the app lets through for this code only.
              tapAt = Date.now();
              var code = link && reelCode(link.getAttribute('href'));
              if (code) {
                grantedCode = code;
                pageGranted = false;
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

          // A tile can stay without a size (display: none, e.g. under the
          // search panel), so waiting for one to be laid out gives up after
          // a few tries, rather than polling for as long as Explore is open.
          // Measuring a tile, or leaving Explore, starts it over.
          var tileRetries = 0;

          // Explore shows Reels as tall (1:2) tiles that link to /p/CODE/, so
          // the link rules miss them. Tell them apart by shape or by the Reels
          // icon on them. Each tile is measured once per link it carries
          // (the grid reuses its tiles as it scrolls).
          function hideReelTiles() {
            if (!hide || location.pathname.indexOf('/explore') !== 0) { tileRetries = 0; return; }
            var tiles = document.querySelectorAll('a[href*="/p/"]');
            var unmeasured = false;
            var measured = false;
            for (var i = 0; i < tiles.length; i++) {
              var tile = tiles[i];
              var href = tile.getAttribute('href');
              if (tile.__i4aHref === href) { continue; }
              var rect = tile.getBoundingClientRect();
              if (!rect.width || !rect.height) { unmeasured = true; continue; } // not laid out yet
              tile.__i4aHref = href;
              measured = true;
              var icon = tile.querySelector('svg[aria-label]');
              var label = icon ? icon.getAttribute('aria-label') : '';
              var reel = /릴스|reel|clip/i.test(label) || rect.height / rect.width >= 1.5;
              if (reel !== tile.hasAttribute('data-i4a-reel-tile')) {
                if (reel) { tile.setAttribute('data-i4a-reel-tile', ''); } else { tile.removeAttribute('data-i4a-reel-tile'); }
              }
            }
            if (measured) { tileRetries = 0; }
            if (unmeasured && tileRetries < 10) {
              tileRetries++;
              setTimeout(schedule, 300);
            }
          }

          // Lets videos go again once they're no longer a Reel player (Reels
          // switched off, or the element reused for something else).
          function releaseVideos() {
            var blocked = document.querySelectorAll('video[data-i4a-blocked]');
            for (var i = 0; i < blocked.length; i++) {
              if (!isReelPlayer(blocked[i])) { blocked[i].removeAttribute('data-i4a-blocked'); }
            }
            var inDirect = location.pathname.indexOf('/direct/') === 0;
            if (grant && (!grant.video.isConnected || (!inDirect && !onGrantedPage()))) { grant = null; }
            if (grantedCode && !inDirect && !onGrantedPage()) { grantedCode = null; }
          }

          function hasOverlay() {
            var dialogs = document.querySelectorAll('[role="dialog"], [aria-modal="true"]');
            for (var i = 0; i < dialogs.length; i++) {
              if (nav && nav.contains(dialogs[i])) { continue; }
              var rect = dialogs[i].getBoundingClientRect();
              if (rect.width > 0 && rect.height > 0 && getComputedStyle(dialogs[i]).visibility !== 'hidden') { return true; }
            }
            return hasBottomSheet();
          }

          // Some of Instagram's sheets (e.g. "Switch accounts") aren't marked
          // as dialogs. Look at what's actually where the native bar sits: if
          // it belongs to something pinned to the screen that isn't
          // Instagram's own bar or the page's whole frame (which holds the
          // main content), a sheet or panel is there and the bar must step
          // aside.
          function hasBottomSheet() {
            var y = window.innerHeight - 40;
            var xs = [window.innerWidth * 0.25, window.innerWidth * 0.5, window.innerWidth * 0.75];
            for (var i = 0; i < xs.length; i++) {
              var el = document.elementFromPoint(xs[i], y);
              for (var depth = 0; el && el !== document.body && el !== document.documentElement && depth < 25; depth++, el = el.parentElement) {
                if (el.hasAttribute('data-i4a-nav')) { break; }
                if (getComputedStyle(el).position !== 'fixed') { continue; }
                if (el.querySelector('main, [role="main"]') || (nav && el.contains(nav))) { break; }
                if (isPageFrame(el)) { break; }
                if (el.getBoundingClientRect().height >= 44) { return true; }
                break;
              }
            }
            return false;
          }

          // A fixed layer spanning the whole screen with no dimmed backdrop
          // is the page itself (the DM inbox is laid out like this), not a
          // sheet over it.
          function isPageFrame(el) {
            var rect = el.getBoundingClientRect();
            if (rect.top > 1 || rect.bottom < window.innerHeight - 1) { return false; }
            var alpha = backgroundAlpha(getComputedStyle(el).backgroundColor);
            return alpha === 0 || alpha === 1;
          }

          function backgroundAlpha(color) {
            var match = /rgba?\\(([^)]*)\\)/.exec(color || '');
            if (!match) { return 0; }
            var parts = match[1].split(/[,\\/\\s]+/).filter(Boolean);
            return parts.length > 3 ? parseFloat(parts[3]) : 1;
          }

          function post(message) {
            try { window.webkit.messageHandlers.\(messageHandlerName).postMessage(message); } catch (e) {}
          }

          function report() {
            var state = collectNavItems();
            state.nav = !!nav;
            state.login = !!document.querySelector('input[type="password"]');
            // Instagram's sheets and viewers sit where the native bar is.
            // Where that bar is hidden anyway, skip measuring the page.
            state.overlay = !NO_BAR.test(location.pathname) && hasOverlay();
            state.navShown = document.documentElement.hasAttribute('data-i4a-show-nav');
            var serialized = JSON.stringify(state);
            if (serialized !== lastReport) {
              lastReport = serialized;
              post(state);
            }
          }

          // Instagram's "new post" button opens a menu or the photo picker that
          // belongs to its own bar, and the picker only opens for a real tap.
          // So show its bar for a while: whatever opens is visible, and if
          // nothing opened, its + is right there to tap directly.
          var showNavUntil = 0;
          // Hiding it again while its menu or picker is still in use would
          // hide those with it (and leave a file picker with nowhere to
          // anchor), so it stays until the page changes, or until a while
          // has passed with nothing of it open.
          var SHOW_NAV_FOR = 30000;
          var showNavPath = null;

          function showInstagramNav() {
            showNavUntil = Date.now() + SHOW_NAV_FOR;
            showNavPath = location.pathname;
            setFlag('data-i4a-show-nav', true);
            setTimeout(refresh, SHOW_NAV_FOR + 50);
          }

          // Any menu, sheet or dialog on screen, including ones inside the bar.
          function hasPopup() {
            var popups = document.querySelectorAll('[role="dialog"], [aria-modal="true"], [role="menu"], [role="listbox"]');
            for (var i = 0; i < popups.length; i++) {
              var rect = popups[i].getBoundingClientRect();
              if (rect.width > 0 && rect.height > 0 && getComputedStyle(popups[i]).visibility !== 'hidden') { return true; }
            }
            return false;
          }

          function updateShownNav() {
            if (!document.documentElement.hasAttribute('data-i4a-show-nav')) { return; }
            var pageChanged = location.pathname !== showNavPath;
            if (!pageChanged && (Date.now() < showNavUntil || hasPopup())) { return; }
            setFlag('data-i4a-show-nav', false);
          }

          // The element that actually handles "new post": the one carrying its
          // label, rather than a wrapper around it.
          function createButton(item) {
            var labelled = item.querySelectorAll('[aria-label]');
            for (var i = 0; i < labelled.length; i++) {
              if (/새로운 게시물|새 게시물|만들기|new post|create/i.test(labelled[i].getAttribute('aria-label') || '')) {
                return labelled[i].closest('a, button, [role="button"], [role="link"]') || labelled[i];
              }
            }
            return item;
          }

          // The native bar shrinks after a deliberate scroll down and grows
          // back on any scroll up or near the top, like Instagram's app. The
          // page tracks this itself, so the app needn't observe the web
          // view's scroll view.
          var lastScrollY = 0;
          var scrollTravel = 0;
          var barCollapsed = false;
          var scrollPath = location.pathname;

          function setBarCollapsed(value) {
            if (value === barCollapsed) { return; }
            barCollapsed = value;
            post({ barCollapsed: value });
          }

          window.addEventListener('scroll', function () {
            var y = window.scrollY || 0;
            var delta = y - lastScrollY;
            lastScrollY = y;
            if (y < 40) {
              scrollTravel = 0;
              setBarCollapsed(false);
              return;
            }
            if ((delta > 0) !== (scrollTravel > 0)) { scrollTravel = 0; }
            scrollTravel += delta;
            if (scrollTravel > 30) { setBarCollapsed(true); }
            else if (scrollTravel < -20) { setBarCollapsed(false); }
          }, { passive: true });

          // A new page starts with the bar shown (the app resets it too).
          function resetScrollOnNewPage() {
            if (location.pathname === scrollPath) { return; }
            scrollPath = location.pathname;
            lastScrollY = window.scrollY || 0;
            scrollTravel = 0;
            barCollapsed = false;
          }

          function refresh() {
            if (!ensureStyle()) { return; }
            resetScrollOnNewPage();
            updateShownNav();
            findNav();
            guardBlankPage();
            improveLogin();
            releaseVideos();
            hideReelTiles();
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
              if (kind === 'create') {
                showInstagramNav();
                el = createButton(el);
              }
              clickAs(el);
              report();
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
