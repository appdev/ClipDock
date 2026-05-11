import Foundation

public final class StorageMaintenanceCoordinator {
    private let openCoreOperation: () -> Result<RustCoreOpenResult, RustCoreError>
    private let runMaintenanceOperation: () -> Result<RustMaintenanceResult, RustCoreError>

    public init(
        openCoreOperation: @escaping () -> Result<RustCoreOpenResult, RustCoreError>,
        runMaintenanceOperation: @escaping () -> Result<RustMaintenanceResult, RustCoreError>
    ) {
        self.openCoreOperation = openCoreOperation
        self.runMaintenanceOperation = runMaintenanceOperation
    }

    public func openCore() -> Result<RustCoreOpenResult, RustCoreError> {
        openCoreOperation()
    }

    public func runMaintenance() -> Result<RustMaintenanceResult, RustCoreError> {
        runMaintenanceOperation()
    }

    public func hasChanges(_ result: RustMaintenanceResult) -> Bool {
        MaintenanceStatusPresenter.hasChanges(result)
    }

    public func statusText(_ result: RustMaintenanceResult) -> String {
        MaintenanceStatusPresenter.statusText(result)
    }
}
