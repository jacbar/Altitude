import CoreGraphics
import XCTest

final class MotionTapPlanTests: XCTestCase {
    private let keyTypes: Set<UInt32> = [
        CGEventType.keyDown.rawValue,
        CGEventType.keyUp.rawValue,
        CGEventType.flagsChanged.rawValue,
    ]
    private let gestureTypes: Set<UInt32> = [29, 30]

    func testDesktopMotionOnly() {
        let plan = MotionTapPlan(mode: SystemMotionMode(
            suppressDesktopMotion: true,
            commandTabEnabled: false,
            commandTabInstantLanding: false
        ))
        XCTAssertTrue(plan.wantsHID)
        XCTAssertTrue(plan.wantsSessionTap)
        XCTAssertTrue(plan.wantsAnyTap)
        XCTAssertEqual(Set(plan.sessionEvents), gestureTypes)
        XCTAssertTrue(keyTypes.isDisjoint(with: Set(plan.sessionEvents)))
    }

    func testCommandTabOnly() {
        let plan = MotionTapPlan(mode: SystemMotionMode(
            suppressDesktopMotion: false,
            commandTabEnabled: true,
            commandTabInstantLanding: false
        ))
        XCTAssertFalse(plan.wantsHID)
        XCTAssertTrue(plan.wantsSessionTap)
        XCTAssertTrue(plan.wantsAnyTap)
        XCTAssertEqual(Set(plan.sessionEvents), keyTypes)
        XCTAssertTrue(gestureTypes.isDisjoint(with: Set(plan.sessionEvents)))
    }

    func testBothOn() {
        let plan = MotionTapPlan(mode: SystemMotionMode(
            suppressDesktopMotion: true,
            commandTabEnabled: true,
            commandTabInstantLanding: true
        ))
        XCTAssertTrue(plan.wantsHID)
        XCTAssertTrue(plan.wantsSessionTap)
        XCTAssertTrue(plan.wantsAnyTap)
        XCTAssertEqual(Set(plan.sessionEvents), gestureTypes.union(keyTypes))
    }

    func testNeither() {
        let plan = MotionTapPlan(mode: .off)
        XCTAssertFalse(plan.wantsHID)
        XCTAssertFalse(plan.wantsSessionTap)
        XCTAssertFalse(plan.wantsAnyTap)
        XCTAssertTrue(plan.sessionEvents.isEmpty)
    }
}
