import XCTest

final class HotkeyIDTests: XCTestCase {
    func testHotkeyIDsAreUniqueAndMatchExpectedRanges() {
        let switchIDs = (1...9).map(HotkeyID.switchDesktop)
        let moveIDs = (1...9).map(HotkeyID.moveDesktop)
        let appShortcutIDs = (0..<ConfigStore.maxAppShortcuts).map(HotkeyID.appShortcut)
        let all = switchIDs + moveIDs + [HotkeyID.maximize, HotkeyID.equalSplit] + appShortcutIDs

        XCTAssertEqual(Set(all).count, all.count)
        XCTAssertEqual(HotkeyID.switchDesktop(1), 1)
        XCTAssertEqual(HotkeyID.moveDesktop(1), 101)
        XCTAssertEqual(HotkeyID.maximize, 200)
        XCTAssertEqual(HotkeyID.equalSplit, 201)
        XCTAssertEqual(HotkeyID.appShortcut(0), 300)
        XCTAssertEqual(HotkeyID.appShortcut(31), 331)
        XCTAssertEqual(switchIDs, Array(1...9).map(UInt32.init))
        XCTAssertEqual(moveIDs, Array(101...109).map(UInt32.init))
    }
}
