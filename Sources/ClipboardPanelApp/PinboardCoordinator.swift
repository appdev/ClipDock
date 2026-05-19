import Foundation

@MainActor
public final class PinboardCoordinator {
    public var onMutationCompleted: ((ClipboardPinboardMutationRequest, RustItemManagementResult) -> Void)?
    public var onStatusTextChanged: ((String) -> Void)?

    private let mutationPerformer: ClipboardPinboardMutationPerformer

    public init(
        mutationPerformer: @escaping ClipboardPinboardMutationPerformer
    ) {
        self.mutationPerformer = mutationPerformer
    }

    public func performMutation(_ mutation: ClipboardPinboardMutationRequest) {
        onStatusTextChanged?(pendingStatusText(for: mutation))
        let mutationPerformer = self.mutationPerformer
        Task { [weak self, mutation, mutationPerformer] in
            let result = await mutationPerformer(mutation)
            guard let self else { return }

            switch result {
            case .success(let mutationResult):
                self.onStatusTextChanged?(self.statusText(for: mutation, result: mutationResult))
                self.onMutationCompleted?(mutation, mutationResult)

            case .failure(let error):
                self.onStatusTextChanged?(AppLocalization.format("pinboard.status.error", defaultValue: "Pinboard：%@", error.code))
            }
        }
    }

    private func pendingStatusText(for mutation: ClipboardPinboardMutationRequest) -> String {
        switch mutation {
        case .create:
            return AppLocalization.text("pinboard.status.creating", defaultValue: "Pinboard：正在创建…")
        case .rename:
            return AppLocalization.text("pinboard.status.renaming", defaultValue: "Pinboard：正在重命名…")
        case .updateColor:
            return AppLocalization.text("pinboard.status.updatingColor", defaultValue: "Pinboard：正在更新颜色…")
        case .delete:
            return AppLocalization.text("pinboard.status.deleting", defaultValue: "Pinboard：正在删除…")
        }
    }

    private func statusText(
        for mutation: ClipboardPinboardMutationRequest,
        result: RustItemManagementResult
    ) -> String {
        switch mutation {
        case .create:
            return result.affectedCount > 0
                ? AppLocalization.text("pinboard.status.created", defaultValue: "Pinboard：已创建")
                : AppLocalization.text("pinboard.status.createFailed", defaultValue: "Pinboard：创建失败")
        case .rename:
            return result.affectedCount > 0
                ? AppLocalization.text("pinboard.status.renamed", defaultValue: "Pinboard：已重命名")
                : AppLocalization.text("pinboard.status.notFound", defaultValue: "Pinboard：未找到")
        case .updateColor:
            return result.affectedCount > 0
                ? AppLocalization.text("pinboard.status.colorUpdated", defaultValue: "Pinboard：颜色已更新")
                : AppLocalization.text("pinboard.status.notFound", defaultValue: "Pinboard：未找到")
        case .delete:
            return result.affectedCount > 0
                ? AppLocalization.format("pinboard.status.deletedWithItems", defaultValue: "Pinboard：已删除，并删除 %lld 条内容", result.affectedCount)
                : AppLocalization.text("pinboard.status.deleted", defaultValue: "Pinboard：已删除")
        }
    }
}
