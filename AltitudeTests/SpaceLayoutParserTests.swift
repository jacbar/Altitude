import XCTest

final class SpaceLayoutParserTests: XCTestCase {
    func testTwoDisplaysAndFullscreenType() {
        let raw: [[String: Any]] = [
            [
                "Display Identifier": "display-a",
                "Current Space": ["ManagedSpaceID": NSNumber(value: UInt64(1))],
                "Spaces": [
                    ["ManagedSpaceID": NSNumber(value: UInt64(1)), "type": 0, "uuid": "desk-1"],
                    ["ManagedSpaceID": NSNumber(value: UInt64(2)), "type": 4],
                    ["id64": NSNumber(value: UInt64(3)), "type": 0, "uuid": "desk-2"],
                ],
            ],
            [
                "Display Identifier": "display-b",
                "Current Space": ["id": NSNumber(value: UInt64(10))],
                "Spaces": [
                    ["id": NSNumber(value: UInt64(10)), "type": 0],
                ],
            ],
        ]
        let layout = SpaceLayoutParser.parse(raw)
        XCTAssertEqual(layout.displays.count, 2)
        XCTAssertEqual(layout.displays[0].spaceIDs, [1, 2, 3])
        XCTAssertEqual(layout.displays[0].currentSpaceID, 1)
        XCTAssertEqual(layout.desktops.map(\.id), [1, 3, 10])
        XCTAssertEqual(layout.desktops.map(\.index), [1, 2, 3])
        XCTAssertFalse(layout.desktops.contains(where: { $0.id == 2 }))
    }

    func testMissingDisplayIdentifierSkipped() {
        let raw: [[String: Any]] = [
            [
                "Current Space": ["ManagedSpaceID": NSNumber(value: UInt64(1))],
                "Spaces": [
                    ["ManagedSpaceID": NSNumber(value: UInt64(1)), "type": 0],
                ],
            ],
            [
                "Display Identifier": "kept",
                "Current Space": ["id64": NSNumber(value: UInt64(5))],
                "Spaces": [
                    ["id64": NSNumber(value: UInt64(5)), "type": 0],
                ],
            ],
        ]
        let layout = SpaceLayoutParser.parse(raw)
        XCTAssertEqual(layout.displays.map(\.identifier), ["kept"])
        XCTAssertEqual(layout.desktops.map(\.id), [5])
    }

    func testID64IsRead() {
        let raw: [[String: Any]] = [
            [
                "Display Identifier": "d",
                "Current Space": ["id64": NSNumber(value: UInt64(77))],
                "Spaces": [
                    ["id64": NSNumber(value: UInt64(77)), "type": 0],
                ],
            ],
        ]
        let layout = SpaceLayoutParser.parse(raw)
        XCTAssertEqual(layout.displays.first?.currentSpaceID, 77)
        XCTAssertEqual(layout.desktops.first?.id, 77)
    }
}
