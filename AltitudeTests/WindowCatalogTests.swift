import CoreGraphics
import XCTest

final class WindowCatalogTests: XCTestCase {
    func testDuplicateCGIDCollapses() {
        let a = ListedWindow(id: 10, title: "Doc", width: 800, height: 600)
        let b = ListedWindow(id: 10, title: "App", width: 800, height: 600)
        let deduped = WindowCatalog.dedupe([a, b], appName: "App")
        XCTAssertEqual(deduped.count, 1)
        XCTAssertEqual(deduped[0].title, "Doc")
    }

    func testWeakTitleSameSizeCollapses() {
        let a = ListedWindow(id: 1, title: "App", width: 900, height: 700)
        let b = ListedWindow(id: 2, title: "Inbox", width: 901, height: 700)
        let deduped = WindowCatalog.dedupe([a, b], appName: "App")
        XCTAssertEqual(deduped.count, 1)
        XCTAssertEqual(deduped[0].title, "Inbox")
        XCTAssertEqual(deduped[0].id, 1)
    }

    func testTwoStrongDifferentTitlesStay() {
        let a = ListedWindow(id: 1, title: "One", width: 900, height: 700)
        let b = ListedWindow(id: 2, title: "Two", width: 900, height: 700)
        let deduped = WindowCatalog.dedupe([a, b], appName: "App")
        XCTAssertEqual(deduped.count, 2)
    }

    func testMergeDropsActiveSpaceCGWhenAXListed() {
        let ax = [ListedWindow(id: 1, title: "Main", width: 800, height: 600, main: true)]
        let cg = [
            ListedWindow(id: 2, title: "Panel", width: 400, height: 400),
            ListedWindow(id: 3, title: "Other Space", width: 700, height: 500),
        ]
        let merged = WindowCatalog.mergeWindows(
            ax: ax,
            cg: cg,
            appName: "App",
            activeSpaceID: 42,
            spaceIDsForWindow: { id in
                id == 2 ? [42] : [99]
            }
        )
        XCTAssertEqual(merged.map(\.id), [1, 3])
    }

    func testOffscreenWeakTitleHelper() {
        XCTAssertTrue(
            WindowCatalog.isHiddenHelper(
                width: 500,
                height: 500,
                title: "Teams",
                onscreen: false,
                appName: "Teams"
            )
        )
        XCTAssertFalse(
            WindowCatalog.isHiddenHelper(
                width: 500,
                height: 500,
                title: "Chat",
                onscreen: false,
                appName: "Teams"
            )
        )
    }
}
