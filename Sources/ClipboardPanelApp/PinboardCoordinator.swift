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
                self.onStatusTextChanged?("Pinboard：\(error.code)")
            }
        }
    }

    private func pendingStatusText(for mutation: ClipboardPinboardMutationRequest) -> String {
        switch mutation {
        case .create:
            return "Pinboard：正在创建…"
        case .rename:
            return "Pinboard：正在重命名…"
        case .updateColor:
            return "Pinboard：正在更新颜色…"
        case .delete:
            return "Pinboard：正在删除…"
        }
    }

    private func statusText(
        for mutation: ClipboardPinboardMutationRequest,
        result: RustItemManagementResult
    ) -> String {
        switch mutation {
        case .create:
            return result.affectedCount > 0 ? "Pinboard：已创建" : "Pinboard：创建失败"
        case .rename:
            return result.affectedCount > 0 ? "Pinboard：已重命名" : "Pinboard：未找到"
        case .updateColor:
            return result.affectedCount > 0 ? "Pinboard：颜色已更新" : "Pinboard：未找到"
        case .delete:
            return result.affectedCount > 0
                ? "Pinboard：已删除，并删除 \(result.affectedCount) 条内容"
                : "Pinboard：已删除"
        }
    }
}
