import XCTest
@testable import Altitude

final class CommandTabOrderTests: XCTestCase {
    func testRowGroupsWindowsThenEmptyApps() {
        let row = commandTabRow(apps: [
            (appID: Int64(1), windows: [1, 2]),
            (appID: Int64(2), windows: [3]),
            (appID: Int64(3), windows: [] as [Int]),
        ])
        XCTAssertEqual(row.map(\.appID), [1, 1, 2, 3] as [Int64])
        XCTAssertEqual(row.map(\.window), [1, 2, 3, nil] as [Int?])
    }

    func testEmptyFrontAppTrailsAfterWindowedApps() {
        let row = commandTabRow(apps: [
            (appID: Int64(1), windows: [] as [Int]),
            (appID: Int64(2), windows: [1, 2]),
        ])
        XCTAssertEqual(row.map(\.appID), [2, 2, 1] as [Int64])
        XCTAssertEqual(
            commandTabOpeningIndex(appIDs: row.map(\.appID), frontAppID: 1, forward: true),
            0
        )
    }

    func testOpeningIndexOnlyFrontApp() {
        let appIDs: [Int64] = [1, 1, 1]
        XCTAssertEqual(commandTabOpeningIndex(appIDs: appIDs, frontAppID: 1, forward: true), 1)
        XCTAssertEqual(commandTabOpeningIndex(appIDs: appIDs, frontAppID: 1, forward: false), 2)
    }

    func testOpeningIndexTwoApps() {
        let appIDs: [Int64] = [1, 1, 2, 2]
        XCTAssertEqual(commandTabOpeningIndex(appIDs: appIDs, frontAppID: 1, forward: true), 2)
        XCTAssertEqual(commandTabOpeningIndex(appIDs: appIDs, frontAppID: 1, forward: false), 3)
    }

    func testOpeningIndexShortLists() {
        XCTAssertEqual(commandTabOpeningIndex(appIDs: [], frontAppID: 1, forward: true), 0)
        XCTAssertEqual(commandTabOpeningIndex(appIDs: [1], frontAppID: 1, forward: true), 0)
        XCTAssertEqual(commandTabOpeningIndex(appIDs: [1], frontAppID: 1, forward: false), 0)
    }
}
