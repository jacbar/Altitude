import XCTest

final class SpaceLayoutTests: XCTestCase {
    func testParseTwoDisplaysFullscreenAndDesktopIndexes() {
        let raw: [[String: Any]] = [
            [
                "Display Identifier": "display-a",
                "Current Space": ["ManagedSpaceID": NSNumber(value: UInt64(10))],
                "Spaces": [
                    ["ManagedSpaceID": NSNumber(value: UInt64(10)), "type": 0, "uuid": "desk-1"],
                    ["ManagedSpaceID": NSNumber(value: UInt64(11)), "type": 0, "uuid": "desk-2"],
                    ["ManagedSpaceID": NSNumber(value: UInt64(12)), "type": 4, "uuid": "full-1"],
                ],
            ],
            [
                "Display Identifier": "display-b",
                "Current Space": ["id64": NSNumber(value: UInt64(20))],
                "Spaces": [
                    ["id64": NSNumber(value: UInt64(20)), "type": 0, "uuid": "desk-3"],
                ],
            ],
        ]

        let layout = ManagedDisplayLayout.parse(raw)

        XCTAssertEqual(layout.displays.count, 2)
        XCTAssertEqual(layout.displays[0].spaceIDs, [10, 11, 12])
        XCTAssertEqual(layout.displays[0].currentSpaceID, 10)
        XCTAssertEqual(layout.displays[1].spaceIDs, [20])
        XCTAssertEqual(layout.displays[1].currentSpaceID, 20)

        XCTAssertEqual(layout.desktops.map(\.index), [1, 2, 3])
        XCTAssertEqual(layout.desktops.map(\.id), [10, 11, 20])
        XCTAssertFalse(layout.desktops.contains { $0.id == 12 })
        XCTAssertEqual(layout.desktops[0].displayIdentifier, "display-a")
        XCTAssertEqual(layout.desktops[2].displayIdentifier, "display-b")
    }

    func testParseSkipsSpaceWithoutID() {
        let raw: [[String: Any]] = [
            [
                "Display Identifier": "display-a",
                "Current Space": ["ManagedSpaceID": NSNumber(value: UInt64(1))],
                "Spaces": [
                    ["type": 0, "uuid": "missing-id"],
                    ["ManagedSpaceID": NSNumber(value: UInt64(1)), "type": 0, "uuid": "ok"],
                ],
            ],
        ]

        let layout = ManagedDisplayLayout.parse(raw)
        XCTAssertEqual(layout.displays[0].spaceIDs, [1])
        XCTAssertEqual(layout.desktops.map(\.id), [1])
    }

    func testParseSkipsDisplayWithoutIdentifier() {
        let raw: [[String: Any]] = [
            [
                "Current Space": ["ManagedSpaceID": NSNumber(value: UInt64(1))],
                "Spaces": [
                    ["ManagedSpaceID": NSNumber(value: UInt64(1)), "type": 0],
                ],
            ],
            [
                "Display Identifier": "kept",
                "Current Space": ["id": NSNumber(value: UInt64(2))],
                "Spaces": [
                    ["id": NSNumber(value: UInt64(2)), "type": 0],
                ],
            ],
        ]

        let layout = ManagedDisplayLayout.parse(raw)
        XCTAssertEqual(layout.displays.count, 1)
        XCTAssertEqual(layout.displays[0].identifier, "kept")
        XCTAssertEqual(layout.desktops.map(\.id), [2])
    }

    func testPreferredRouteNearestCandidate() {
        let route = preferredSpaceRoute(
            candidateIDs: [40, 10],
            displaySpaceIDs: [10, 20, 30, 40],
            currentID: 20
        )
        XCTAssertEqual(
            route,
            .posted(steps: 1, from: 1, to: 0, destinationID: 10)
        )
    }

    func testPreferredRouteOtherDisplay() {
        let route = preferredSpaceRoute(
            candidateIDs: [99, 100],
            displaySpaceIDs: [10, 20, 30],
            currentID: 20
        )
        XCTAssertEqual(route, .otherDisplay)
    }

    func testPreferredRouteAlreadyThereWhenCandidateIsCurrent() {
        let route = preferredSpaceRoute(
            candidateIDs: [20, 30],
            displaySpaceIDs: [10, 20, 30],
            currentID: 20
        )
        XCTAssertEqual(route, .alreadyThere)
    }

    func testMultiDisplayPreferredRouteAlreadyThereOnOtherDisplayCurrent() {
        let displays = [
            DisplaySpaceRouteInput(identifier: "a", spaceIDs: [10, 11], currentID: 10),
            DisplaySpaceRouteInput(identifier: "b", spaceIDs: [20, 21], currentID: 21),
        ]
        let result = preferredSpaceRoute(
            candidateIDs: [21],
            displays: displays,
            activeDisplayIdentifier: "a"
        )
        XCTAssertEqual(result.displayIdentifier, "b")
        XCTAssertEqual(result.route, .alreadyThere)
    }

    func testMultiDisplayPreferredRoutePostsHopOnOtherDisplay() {
        let displays = [
            DisplaySpaceRouteInput(identifier: "a", spaceIDs: [10, 11], currentID: 10),
            DisplaySpaceRouteInput(identifier: "b", spaceIDs: [20, 21, 22], currentID: 20),
        ]
        let result = preferredSpaceRoute(
            candidateIDs: [22],
            displays: displays,
            activeDisplayIdentifier: "a"
        )
        XCTAssertEqual(result.displayIdentifier, "b")
        XCTAssertEqual(
            result.route,
            .posted(steps: 2, from: 0, to: 2, destinationID: 22)
        )
    }

    func testMultiDisplayPreferredRouteEmptyCandidatesAreAlreadyThere() {
        let displays = [
            DisplaySpaceRouteInput(identifier: "a", spaceIDs: [10], currentID: 10),
        ]
        let result = preferredSpaceRoute(
            candidateIDs: [],
            displays: displays,
            activeDisplayIdentifier: "a"
        )
        XCTAssertEqual(result.displayIdentifier, "a")
        XCTAssertEqual(result.route, .alreadyThere)
    }

    func testMultiDisplayPreferredRouteUnknownCandidatesAreOtherDisplay() {
        let displays = [
            DisplaySpaceRouteInput(identifier: "a", spaceIDs: [10, 11], currentID: 10),
            DisplaySpaceRouteInput(identifier: "b", spaceIDs: [20], currentID: 20),
        ]
        let result = preferredSpaceRoute(
            candidateIDs: [99, 100],
            displays: displays,
            activeDisplayIdentifier: "a"
        )
        XCTAssertNil(result.displayIdentifier)
        XCTAssertEqual(result.route, .otherDisplay)
    }

    func testMultiDisplayPreferredRouteSameDisplayNearestWinsOverOtherDisplay() {
        let displays = [
            DisplaySpaceRouteInput(identifier: "a", spaceIDs: [10, 11, 12], currentID: 10),
            DisplaySpaceRouteInput(identifier: "b", spaceIDs: [20, 21], currentID: 21),
        ]
        // Active display owns 12; other display's current (21) is also a candidate —
        // same-display nearest must still win.
        let result = preferredSpaceRoute(
            candidateIDs: [12, 21],
            displays: displays,
            activeDisplayIdentifier: "a"
        )
        XCTAssertEqual(result.displayIdentifier, "a")
        XCTAssertEqual(
            result.route,
            .posted(steps: 2, from: 0, to: 2, destinationID: 12)
        )
    }

    func testMultiDisplayPreferredRouteFallsThroughWhenActiveCurrentMissingFromStrip() {
        let displays = [
            // Active owns candidate 12, but currentID is not on the strip.
            DisplaySpaceRouteInput(identifier: "a", spaceIDs: [10, 11, 12], currentID: 99),
            DisplaySpaceRouteInput(identifier: "b", spaceIDs: [20, 21, 22], currentID: 20),
        ]
        let result = preferredSpaceRoute(
            candidateIDs: [12, 22],
            displays: displays,
            activeDisplayIdentifier: "a"
        )
        XCTAssertEqual(result.displayIdentifier, "b")
        XCTAssertEqual(
            result.route,
            .posted(steps: 2, from: 0, to: 2, destinationID: 22)
        )
    }

    func testDigitSwitchRouteSameDisplayHop() {
        let route = digitSwitchRoute(
            targetSpaceID: 30,
            displaySpaceIDs: [10, 20, 30],
            currentID: 10
        )
        XCTAssertEqual(
            route,
            .posted(steps: 2, from: 0, to: 2, destinationID: 30)
        )
    }

    func testDigitSwitchRouteAlreadyThere() {
        let route = digitSwitchRoute(
            targetSpaceID: 20,
            displaySpaceIDs: [10, 20, 30],
            currentID: 20
        )
        XCTAssertEqual(route, .alreadyThere)
    }

    func testDigitSwitchRouteMultiStepOnNonActiveDisplayStrip() {
        // External display strip while focus is elsewhere: hop from that strip's current Space.
        let otherDisplayStrip: [CGSSpaceID] = [40, 41, 42, 43]
        let route = digitSwitchRoute(
            targetSpaceID: 43,
            displaySpaceIDs: otherDisplayStrip,
            currentID: 41
        )
        XCTAssertEqual(
            route,
            .posted(steps: 2, from: 1, to: 3, destinationID: 43)
        )
    }

    func testDigitSwitchRouteMissingIDsAreOtherDisplay() {
        XCTAssertEqual(
            digitSwitchRoute(targetSpaceID: 99, displaySpaceIDs: [10, 20], currentID: 10),
            .otherDisplay
        )
        XCTAssertEqual(
            digitSwitchRoute(targetSpaceID: 20, displaySpaceIDs: [10, 20], currentID: 99),
            .otherDisplay
        )
    }

    func testOneSpaceRouteEdgesAreAlreadyThere() {
        let spaces: [CGSSpaceID] = [10, 20, 30]
        XCTAssertEqual(
            oneSpaceRoute(direction: .previous, displaySpaceIDs: spaces, currentIndex: 0),
            .alreadyThere
        )
        XCTAssertEqual(
            oneSpaceRoute(direction: .next, displaySpaceIDs: spaces, currentIndex: 2),
            .alreadyThere
        )
    }

    func testOneSpaceRoutePostsSingleStep() {
        let spaces: [CGSSpaceID] = [10, 20, 30]
        XCTAssertEqual(
            oneSpaceRoute(direction: .next, displaySpaceIDs: spaces, currentIndex: 0),
            .posted(steps: 1, from: 0, to: 1, destinationID: 20)
        )
        XCTAssertEqual(
            oneSpaceRoute(direction: .previous, displaySpaceIDs: spaces, currentIndex: 2),
            .posted(steps: 1, from: 2, to: 1, destinationID: 20)
        )
    }

    func testLivePredictionDoesNotMutateAndShouldExpire() {
        let now = Date()
        var prediction: SpacePrediction? = SpacePrediction(
            spaceID: 42,
            displayIdentifier: "display-a",
            expiry: now.addingTimeInterval(2)
        )

        let live = prediction?.live(activeID: 7, now: now)
        XCTAssertEqual(live?.spaceID, 42)
        XCTAssertEqual(prediction?.spaceID, 42)

        XCTAssertFalse(prediction.shouldExpire(activeID: 7, now: now))
        XCTAssertTrue(prediction.shouldExpire(activeID: 42, now: now))
        XCTAssertTrue(prediction.shouldExpire(activeID: 7, now: now.addingTimeInterval(3)))
        // Focus moved to another display — drop same-strip hop prediction.
        XCTAssertTrue(
            prediction.shouldExpire(
                activeID: 7,
                now: now,
                liveActiveDisplayIdentifier: "display-b"
            )
        )
        XCTAssertFalse(
            prediction.shouldExpire(
                activeID: 7,
                now: now,
                liveActiveDisplayIdentifier: "display-a"
            )
        )

        prediction = nil
        XCTAssertTrue(prediction.shouldExpire(activeID: 7, now: now))
    }

    func testNeedsCrossDisplayFocusUsesLiveDisplayOnly() {
        XCTAssertTrue(
            needsCrossDisplayFocus(
                targetDisplayIdentifier: "main",
                liveActiveDisplayIdentifier: "external"
            )
        )
        XCTAssertFalse(
            needsCrossDisplayFocus(
                targetDisplayIdentifier: "main",
                liveActiveDisplayIdentifier: "main"
            )
        )
        // Unknown live focus — still try to pull focus before swiping.
        XCTAssertTrue(
            needsCrossDisplayFocus(
                targetDisplayIdentifier: "main",
                liveActiveDisplayIdentifier: nil
            )
        )
    }
}
