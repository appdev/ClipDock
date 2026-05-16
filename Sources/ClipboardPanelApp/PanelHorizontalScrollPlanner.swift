import CoreGraphics

public enum PanelHorizontalScrollMode: Equatable, Sendable {
    case none
    case nativeHorizontal
    case projectedVertical
}

public struct PanelHorizontalScrollInput: Equatable, Sendable {
    public let horizontalDelta: CGFloat
    public let verticalDelta: CGFloat
    public let hasPreciseScrollingDeltas: Bool

    public init(
        horizontalDelta: CGFloat,
        verticalDelta: CGFloat,
        hasPreciseScrollingDeltas: Bool
    ) {
        self.horizontalDelta = horizontalDelta
        self.verticalDelta = verticalDelta
        self.hasPreciseScrollingDeltas = hasPreciseScrollingDeltas
    }
}

public struct PanelHorizontalScrollPlan: Equatable, Sendable {
    public let mode: PanelHorizontalScrollMode
    public let contentOffsetDelta: CGFloat

    public init(mode: PanelHorizontalScrollMode, contentOffsetDelta: CGFloat) {
        self.mode = mode
        self.contentOffsetDelta = contentOffsetDelta
    }

    public static let none = PanelHorizontalScrollPlan(mode: .none, contentOffsetDelta: 0)
}

public enum PanelHorizontalScrollPlanner {
    public struct Configuration: Equatable, Sendable {
        public let lineDeltaMultiplier: CGFloat
        public let minimumEventDelta: CGFloat

        public init(
            lineDeltaMultiplier: CGFloat = 18,
            minimumEventDelta: CGFloat = 0.05
        ) {
            self.lineDeltaMultiplier = lineDeltaMultiplier
            self.minimumEventDelta = minimumEventDelta
        }
    }

    public static func plan(
        for input: PanelHorizontalScrollInput,
        configuration: Configuration = Configuration()
    ) -> PanelHorizontalScrollPlan {
        let horizontalDelta = normalizedDelta(
            input.horizontalDelta,
            hasPreciseScrollingDeltas: input.hasPreciseScrollingDeltas,
            configuration: configuration
        )
        let verticalDelta = normalizedDelta(
            input.verticalDelta,
            hasPreciseScrollingDeltas: input.hasPreciseScrollingDeltas,
            configuration: configuration
        )

        guard abs(horizontalDelta) >= configuration.minimumEventDelta
            || abs(verticalDelta) >= configuration.minimumEventDelta
        else {
            return .none
        }

        if abs(horizontalDelta) >= abs(verticalDelta),
           abs(horizontalDelta) >= configuration.minimumEventDelta {
            return PanelHorizontalScrollPlan(
                mode: .nativeHorizontal,
                contentOffsetDelta: -horizontalDelta
            )
        }

        return PanelHorizontalScrollPlan(
            mode: .projectedVertical,
            contentOffsetDelta: -verticalDelta
        )
    }

    private static func normalizedDelta(
        _ delta: CGFloat,
        hasPreciseScrollingDeltas: Bool,
        configuration: Configuration
    ) -> CGFloat {
        guard delta != 0 else { return 0 }
        return hasPreciseScrollingDeltas
            ? delta
            : delta * configuration.lineDeltaMultiplier
    }
}
