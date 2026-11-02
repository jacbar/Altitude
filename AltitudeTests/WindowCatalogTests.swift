import XCTest

final class WindowCatalogTests: XCTestCase {
    func testChatGPTStyleTripleCollapsesToLargest() {
        let windows = [
            ListedWindow(id: 1, title: "", width: 2040, height: 1273),
            ListedWindow(id: 2, title: "", width: 960, height: 720),
            ListedWindow(id: 3, title: "ChatGPT", width: 675, height: 720),
        ]
        let result = WindowCatalog.collapseRedundantWeakWindows(windows, appName: "ChatGPT")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, 1)
    }

    func testStrongTitlesSurviveSmallerWeakHelper() {
        let windows = [
            ListedWindow(id: 10, title: "Chat A", width: 1200, height: 800),
            ListedWindow(id: 11, title: "Chat B", width: 1100, height: 700),
            ListedWindow(id: 12, title: "", width: 675, height: 720),
        ]
        let result = WindowCatalog.collapseRedundantWeakWindows(windows, appName: "ChatGPT")
        XCTAssertEqual(result.map(\.id), [10, 11])
        XCTAssertEqual(result.map(\.title), ["Chat A", "Chat B"])
    }

    func testNearTieWeaksAreBothKept() {
        let windows = [
            ListedWindow(id: 20, title: "", width: 1200, height: 800),
            ListedWindow(id: 21, title: "", width: 1190, height: 800),
        ]
        let result = WindowCatalog.collapseRedundantWeakWindows(windows, appName: "ChatGPT")
        XCTAssertEqual(result.map(\.id), [20, 21])
    }

    func testTeamsTwinCollapsesToSpecificTitle() {
        let windows = [
            ListedWindow(id: 1, title: "", width: 1400, height: 900),
            ListedWindow(id: 2, title: "Standup notes", width: 1400, height: 900),
        ]
        let result = WindowCatalog.dedupe(windows, appName: "Microsoft Teams")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "Standup notes")
        XCTAssertEqual(result.first?.id, 1)

        let appNamed = [
            ListedWindow(id: 3, title: "Microsoft Teams", width: 1400, height: 900),
            ListedWindow(id: 4, title: "Standup notes", width: 1400, height: 900),
        ]
        let appNamedResult = WindowCatalog.dedupe(appNamed, appName: "Microsoft Teams")
        XCTAssertEqual(appNamedResult.count, 1)
        XCTAssertEqual(appNamedResult.first?.title, "Standup notes")
    }

    func testTwoStrongTitlesStaySeparate() {
        let windows = [
            ListedWindow(id: 1, title: "Doc A", width: 1400, height: 900),
            ListedWindow(id: 2, title: "Doc B", width: 1400, height: 900),
        ]
        let result = WindowCatalog.dedupe(windows, appName: "Pages")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.title), ["Doc A", "Doc B"])
    }

    func testHiddenHelperSizes() {
        XCTAssertTrue(
            WindowCatalog.isHiddenHelper(
                width: 500,
                height: 500,
                title: "",
                onscreen: false,
                appName: "Arc"
            )
        )
        XCTAssertTrue(
            WindowCatalog.isHiddenHelper(
                width: 800,
                height: 600,
                title: "Arc",
                onscreen: false,
                appName: "Arc"
            )
        )
        XCTAssertFalse(
            WindowCatalog.isHiddenHelper(
                width: 500,
                height: 500,
                title: "",
                onscreen: true,
                appName: "Arc"
            )
        )
    }

    func testMergeWindowsMatchingCGUpdatesAX() {
        let ax = [ListedWindow(id: nil, title: "", width: 1200, height: 800, main: true)]
        let cg = [ListedWindow(id: 42, title: "Inbox", width: 1200, height: 800)]
        let merged = WindowCatalog.mergeWindows(
            ax: ax,
            cg: cg,
            appName: "Mail",
            isOnActiveSpace: { _ in true }
        )
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.id, 42)
        XCTAssertEqual(merged.first?.title, "Inbox")
        XCTAssertTrue(merged.first?.main ?? false)
    }

    func testMergeWindowsDropsUnmatchedOnActiveSpace() {
        let ax = [ListedWindow(id: 1, title: "Main", width: 1200, height: 800)]
        let cg = [
            ListedWindow(id: 1, title: "Main", width: 1200, height: 800),
            ListedWindow(id: 99, title: "Settings", width: 640, height: 480),
        ]
        let merged = WindowCatalog.mergeWindows(
            ax: ax,
            cg: cg,
            appName: "Rex",
            isOnActiveSpace: { $0 == 99 }
        )
        XCTAssertEqual(merged.map(\.id), [1])
    }

    func testMergeWindowsAppendsOtherSpaceCG() {
        let ax = [ListedWindow(id: 1, title: "Main", width: 1200, height: 800)]
        let cg = [ListedWindow(id: 7, title: "Other Space", width: 1000, height: 700)]
        let merged = WindowCatalog.mergeWindows(
            ax: ax,
            cg: cg,
            appName: "Safari",
            isOnActiveSpace: { _ in false }
        )
        XCTAssertEqual(merged.map(\.id), [1, 7])
    }

    func testMergeWindowsNilClosureAppendsUnmatchedCG() {
        let ax: [ListedWindow] = []
        let cg = [ListedWindow(id: 7, title: "Only CG", width: 1000, height: 700)]
        let merged = WindowCatalog.mergeWindows(
            ax: ax,
            cg: cg,
            appName: "Safari",
            isOnActiveSpace: nil
        )
        XCTAssertEqual(merged.map(\.id), [7])
    }
}
