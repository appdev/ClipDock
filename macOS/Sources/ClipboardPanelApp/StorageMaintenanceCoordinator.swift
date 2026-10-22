import Foundation

@MainActor
public final class StorageMaintenanceCoordinator {
    private let openCoreOperation: () async -> Result<RustCoreOpenResult, RustCoreError>
    private let runMaintenanceOperation: () async -> Result<RustMaintenanceResult, RustCoreError>

    public init(
        openCoreOperation: @escaping () async -> Result<RustCoreOpenResult, RustCoreError>,
        runMaintenanceOperation: @escaping () async -> Result<RustMaintenanceResult, RustCoreError>
    ) {
        self.openCoreOperation = openCoreOperation
        self.runMaintenanceOperation = runMaintenanceOperation
    }

    public func openCore() async -> Result<RustCoreOpenResult, RustCoreError> {
        await openCoreOperation()
    }

    public func runMaintenance() async -> Result<RustMaintenanceResult, RustCoreError> {
        await runMaintenanceOperation()
    }

    public func hasChanges(_ result: RustMaintenanceResult) -> Bool {
        MaintenanceStatusPresenter.hasChanges(result)
    }

    public func statusText(_ result: RustMaintenanceResult) -> String {
        MaintenanceStatusPresenter.statusText(result)
    }
}
