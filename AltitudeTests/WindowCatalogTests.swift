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
}
