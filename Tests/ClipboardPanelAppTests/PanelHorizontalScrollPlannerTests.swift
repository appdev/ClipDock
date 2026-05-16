import Testing
@testable import ClipboardPanelApp

struct PanelHorizontalScrollPlannerTests {
    @Test
    func preciseVerticalWheelProjectsToHorizontalWithoutMultiplier() {
        let plan = PanelHorizontalScrollPlanner.plan(for: PanelHorizontalScrollInput(
            horizontalDelta: 0,
            verticalDelta: -3,
            hasPreciseScrollingDeltas: true
        ))

        #expect(plan.mode == .projectedVertical)
        #expect(plan.contentOffsetDelta == 3)
    }

    @Test
    func nonPreciseWheelUsesLineDeltaMultiplier() {
        let plan = PanelHorizontalScrollPlanner.plan(for: PanelHorizontalScrollInput(
            horizontalDelta: 0,
            verticalDelta: -3,
            hasPreciseScrollingDeltas: false
        ))

        #expect(plan.mode == .projectedVertical)
        #expect(plan.contentOffsetDelta == 54)
    }

    @Test
    func nativeHorizontalDeltaWinsWhenDominant() {
        let plan = PanelHorizontalScrollPlanner.plan(for: PanelHorizontalScrollInput(
            horizontalDelta: -8,
            verticalDelta: -3,
            hasPreciseScrollingDeltas: true
        ))

        #expect(plan.mode == .nativeHorizontal)
        #expect(plan.contentOffsetDelta == 8)
    }

    @Test
    func horizontalDeltaWinsTieToPreserveNativeTrackpadIntent() {
        let plan = PanelHorizontalScrollPlanner.plan(for: PanelHorizontalScrollInput(
            horizontalDelta: -4,
            verticalDelta: 4,
            hasPreciseScrollingDeltas: true
        ))

        #expect(plan.mode == .nativeHorizontal)
        #expect(plan.contentOffsetDelta == 4)
    }

    @Test
    func tinyDeltasAreIgnored() {
        let plan = PanelHorizontalScrollPlanner.plan(for: PanelHorizontalScrollInput(
            horizontalDelta: 0.01,
            verticalDelta: -0.02,
            hasPreciseScrollingDeltas: true
        ))

        #expect(plan == .none)
    }
}
