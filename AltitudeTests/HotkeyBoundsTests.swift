import XCTest
@testable import Altitude

final class HotkeyBoundsTests: XCTestCase {
    func testEffectiveMaxHotkeySpace() {
        XCTAssertEqual(effectiveMaxHotkeySpace(maxSpace: 16, spaceCount: 12), 9)
        XCTAssertEqual(effectiveMaxHotkeySpace(maxSpace: 5, spaceCount: 12), 5)
        XCTAssertEqual(effectiveMaxHotkeySpace(maxSpace: 9, spaceCount: 0), 1)
        XCTAssertEqual(effectiveMaxHotkeySpace(maxSpace: 9, spaceCount: 3), 3)
    }
}
