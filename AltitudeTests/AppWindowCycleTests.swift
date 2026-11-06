import XCTest

final class AppWindowCycleTests: XCTestCase {
    func testNextRequiresTwoWindows() {
        let only = window(1, title: "Only", main: true)
        XCTAssertNil(AppWindowCycle.next(order: [], focusedID: nil))
        XCTAssertNil(AppWindowCycle.next(order: [only], focusedID: 1))
    }

    func testNextAdvancesAndWraps() {
        let order = [window(1, title: "A", main: true), window(2, title: "B"), window(3, title: "C")]
        XCTAssertEqual(AppWindowCycle.next(order: order, focusedID: 1)?.id, 2)
        XCTAssertEqual(AppWindowCycle.next(order: order, focusedID: 2)?.id, 3)
        XCTAssertEqual(AppWindowCycle.next(order: order, focusedID: 3)?.id, 1)
    }

    func testNextPrefersPendingOverStaleFocus() {
        let order = [window(1, title: "A", main: true), window(2, title: "B"), window(3, title: "C")]
        let pending = window(2, title: "B")
        XCTAssertEqual(
            AppWindowCycle.next(order: order, focusedID: 1, pending: pending)?.id,
            3
        )
    }

    func testNextIgnoresPendingMissingFromOrder() {
        let order = [window(1, title: "A", main: true), window(2, title: "B")]
        let closed = window(9, title: "Gone")
        XCTAssertEqual(
            AppWindowCycle.next(order: order, focusedID: 1, pending: closed)?.id,
            2
        )
    }

    func testNextUsesMainWhenFocusIDMissing() {
        let order = [window(1, title: "A"), window(2, title: "B", main: true), window(3, title: "C")]
        XCTAssertEqual(AppWindowCycle.next(order: order, focusedID: nil)?.id, 3)
        XCTAssertEqual(AppWindowCycle.next(order: order, focusedID: 0)?.id, 3)
    }

    func testNextLandsOnFirstWhenFocusUnknown() {
        let order = [window(4, title: "A"), window(5, title: "B")]
        XCTAssertEqual(AppWindowCycle.next(order: order, focusedID: 99)?.id, 4)
    }

    func testStabilizedOrderSurvivesRaise() {
        let previous = [window(1, title: "A", main: true), window(2, title: "B"), window(3, title: "C")]
        let latest = [window(2, title: "B renamed", main: true), window(1, title: "A"), window(3, title: "C")]
        let order = AppWindowCycle.stabilizedOrder(previous: previous, latest: latest)
        XCTAssertEqual(order.map(\.id), [1, 2, 3])
        XCTAssertEqual(order.map(\.title), ["A", "B renamed", "C"])
        XCTAssertEqual(order.map(\.main), [false, true, false])
    }

    func testStabilizedOrderResetsWhenWindowSetChanges() {
        let previous = [window(1, title: "A"), window(2, title: "B")]
        let opened = [window(1, title: "A"), window(2, title: "B"), window(3, title: "C")]
        XCTAssertEqual(
            AppWindowCycle.stabilizedOrder(previous: previous, latest: opened).map(\.id),
            [1, 2, 3]
        )
        let closed = [window(2, title: "B")]
        XCTAssertEqual(
            AppWindowCycle.stabilizedOrder(previous: previous, latest: closed).map(\.id),
            [2]
        )
        XCTAssertEqual(
            AppWindowCycle.stabilizedOrder(previous: nil, latest: opened).map(\.id),
            [1, 2, 3]
        )
    }

    func testRepeatedPressesVisitEachWindowOnce() {
        let snapshot = [window(1, title: "A", main: true), window(2, title: "B"), window(3, title: "C")]
        var order = AppWindowCycle.stabilizedOrder(previous: nil, latest: snapshot)
        var pending: ListedWindow?
        let focused: CGWindowID? = 1
        var seen: [CGWindowID] = []
        for _ in 0..<3 {
            let next = AppWindowCycle.next(order: order, focusedID: focused, pending: pending)
            guard let next, let id = next.id else {
                XCTFail("expected a next window")
                return
            }
            seen.append(id)
            pending = next
            // Live z-order puts the raised window first; Accessibility focus stays behind.
            let raised = snapshot
                .map { window($0.id ?? 0, title: $0.title, main: $0.id == id) }
                .sorted { lhs, rhs in
                    if lhs.main != rhs.main { return lhs.main }
                    return (lhs.id ?? 0) > (rhs.id ?? 0)
                }
            order = AppWindowCycle.stabilizedOrder(previous: order, latest: raised)
        }
        XCTAssertEqual(seen, [2, 3, 1])
        XCTAssertEqual(order.map(\.id), [1, 2, 3])
    }

    private func window(_ id: CGWindowID, title: String, main: Bool = false) -> ListedWindow {
        ListedWindow(id: id, title: title, width: 800, height: 600, main: main)
    }
}
