import XCTest
@testable import I4A

final class WebTabTests: XCTestCase {
    func testActiveTab() {
        XCTAssertEqual(WebTab.active(forPath: "/", profilePath: nil), .home)
        XCTAssertEqual(WebTab.active(forPath: "", profilePath: nil), .home)
        XCTAssertEqual(WebTab.active(forPath: "/explore/", profilePath: nil), .explore)
        XCTAssertEqual(WebTab.active(forPath: "/explore/search/", profilePath: nil), .explore)
        XCTAssertEqual(WebTab.active(forPath: "/direct/inbox/", profilePath: nil), .direct)
        XCTAssertEqual(WebTab.active(forPath: "/me/", profilePath: "/me/"), .profile)
        XCTAssertEqual(WebTab.active(forPath: "/me/tagged/", profilePath: "/me/"), .profile)
        XCTAssertNil(WebTab.active(forPath: "/someone/", profilePath: "/me/"))
        XCTAssertNil(WebTab.active(forPath: "/p/abc/", profilePath: nil))
    }

    func testPagesThatHideTheBar() {
        XCTAssertTrue(WebTab.hidesBar(onPath: "/direct/t/123/"))
        XCTAssertTrue(WebTab.hidesBar(onPath: "/accounts/login/"))
        XCTAssertTrue(WebTab.hidesBar(onPath: "/stories/someone/1/"))
        XCTAssertFalse(WebTab.hidesBar(onPath: "/direct/inbox/"))
        XCTAssertFalse(WebTab.hidesBar(onPath: "/"))
    }

    func testFallbackPaths() {
        XCTAssertEqual(WebTab.home.fallbackPath(profilePath: nil), "/")
        XCTAssertEqual(WebTab.direct.fallbackPath(profilePath: nil), "/direct/inbox/")
        XCTAssertEqual(WebTab.profile.fallbackPath(profilePath: "/me/"), "/me/")
        XCTAssertNil(WebTab.profile.fallbackPath(profilePath: nil))
        XCTAssertNil(WebTab.create.fallbackPath(profilePath: "/me/"))
    }

    func testBarStaysWhereInstagramDropsItsOwn() {
        XCTAssertTrue(WebTab.keepsBarWithoutInstagramNav(onPath: "/direct/inbox/"))
        XCTAssertTrue(WebTab.keepsBarWithoutInstagramNav(onPath: "/direct/requests/"))
        XCTAssertFalse(WebTab.keepsBarWithoutInstagramNav(onPath: "/direct/t/123/"))
        XCTAssertFalse(WebTab.keepsBarWithoutInstagramNav(onPath: "/p/abc/"))
    }
}
