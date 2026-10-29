import XCTest
@testable import I4A

final class NavigationPolicyTests: XCTestCase {
    private func url(_ string: String) -> URL { URL(string: string)! }

    func testDetectsReelsURLs() {
        let reels = [
            "https://www.instagram.com/reels/",
            "https://www.instagram.com/reels",
            "https://www.instagram.com/reels?igsh=abc",
            "https://www.instagram.com/reels/C1a2b3/",
            "https://www.instagram.com/reels/audio/123/",
            "https://www.instagram.com/reel/C1a2b3/",
            "https://instagram.com/reel/C1a2b3/?utm_source=ig_web_copy_link",
            "https://www.instagram.com/someone/reels/",
            "https://www.instagram.com/someone/reel/C1a2b3/",
            "https://m.instagram.com/REELS/",
        ]
        for string in reels {
            XCTAssertTrue(NavigationPolicy.isReels(url(string)), string)
        }
    }

    func testAllowsNonReelsURLs() {
        let notReels = [
            "https://www.instagram.com/",
            "https://www.instagram.com/?variant=following",
            "https://www.instagram.com/p/C1a2b3/",
            "https://www.instagram.com/someone/",
            "https://www.instagram.com/someone/tagged/",
            "https://www.instagram.com/direct/inbox/",
            "https://www.instagram.com/explore/",
            "https://www.instagram.com/stories/someone/123/",
            "https://www.instagram.com/reelsfan/",
            "https://www.facebook.com/reels/",
            "https://example.com/reel/abc/",
        ]
        for string in notReels {
            XCTAssertFalse(NavigationPolicy.isReels(url(string)), string)
        }
        XCTAssertFalse(NavigationPolicy.isReels(nil))
    }

    func testAllowedHosts() {
        XCTAssertTrue(NavigationPolicy.isAllowedHost("www.instagram.com"))
        XCTAssertTrue(NavigationPolicy.isAllowedHost("instagram.com"))
        XCTAssertTrue(NavigationPolicy.isAllowedHost("l.instagram.com"))
        XCTAssertTrue(NavigationPolicy.isAllowedHost("m.facebook.com"))
        XCTAssertTrue(NavigationPolicy.isAllowedHost("WWW.INSTAGRAM.COM"))
        XCTAssertFalse(NavigationPolicy.isAllowedHost("evilinstagram.com"))
        XCTAssertFalse(NavigationPolicy.isAllowedHost("instagram.com.evil.net"))
        XCTAssertFalse(NavigationPolicy.isAllowedHost("example.com"))
        XCTAssertFalse(NavigationPolicy.isAllowedHost(""))
        XCTAssertFalse(NavigationPolicy.isAllowedHost(nil))
    }

    func testDecisions() {
        func decide(_ s: String, main: Bool = true, hide: Bool = true) -> NavigationDecision {
            NavigationPolicy.decide(url: url(s), isMainFrame: main, hideReels: hide)
        }
        XCTAssertEqual(decide("https://www.instagram.com/"), .allow)
        XCTAssertEqual(decide("https://www.instagram.com/reels/"), .blockReels)
        XCTAssertEqual(decide("https://www.instagram.com/reels/", hide: false), .allow)
        XCTAssertEqual(decide("https://www.facebook.com/login/"), .allow)
        XCTAssertEqual(decide("https://example.com/"), .openExternally)
        XCTAssertEqual(decide("https://example.com/", main: false), .allow)
        XCTAssertEqual(decide("instagram://user?username=x"), .cancel)
        XCTAssertEqual(decide("itms-apps://apps.apple.com/app/id389801252"), .cancel)
        XCTAssertEqual(decide("instagram://media", main: false), .cancel)
        XCTAssertEqual(decide("mailto:hi@example.com"), .openExternally)
        XCTAssertEqual(decide("about:blank"), .allow)
    }
}
