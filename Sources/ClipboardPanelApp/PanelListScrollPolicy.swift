import Foundation

public enum PanelListScrollAction: Equatable, Sendable {
    case preserveCurrentPosition
    case resetToLeadingEdge

    public var preserveScrollPosition: Bool {
        self == .preserveCurrentPosition
    }

    public var shouldScrollSelectedItem: Bool {
        self == .preserveCurrentPosition
    }
}

public enum PanelListScrollPolicy {
    public static func action(
        previousOrderedItemIDs: [String],
        nextOrderedItemIDs: [String],
        isAppendUpdate: Bool,
        preserveOnStructuralChange: Bool = false
    ) -> PanelListScrollAction {
        if isAppendUpdate {
            return .preserveCurrentPosition
        }

        if previousOrderedItemIDs == nextOrderedItemIDs {
            return .preserveCurrentPosition
        }

        if preserveOnStructuralChange {
            return .preserveCurrentPosition
        }

        return .resetToLeadingEdge
    }
}
