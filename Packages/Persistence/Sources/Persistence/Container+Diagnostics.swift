import FactoryKit

public extension Container {
    /// Diagnostics telemetry service. Defaults to a no-op implementation until
    /// the app composition root registers the production instance.
    @MainActor
    var diagnosticsService: Factory<any DiagnosticsServicing> {
        self { NoopDiagnosticsService() }
            .scope(.singleton)
            .onPreview { NoopDiagnosticsService() }
            .onTest { NoopDiagnosticsService() }
    }
}

@MainActor
public func registerProductionDiagnosticsService(_ service: any DiagnosticsServicing) {
    Container.shared.diagnosticsService.register { service }
}
