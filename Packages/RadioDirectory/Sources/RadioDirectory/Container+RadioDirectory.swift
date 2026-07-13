import FactoryKit

public extension Container {
    /// The station directory, resolved via Factory instead of direct instantiation.
    /// Defaults to the keyless Radio-Browser client; `AppDependencies.bootstrap()`
    /// overrides this with the production (preferred + caching) decorated instance
    /// via ``registerProductionRadioDirectory(_:)``.
    var radioDirectory: Factory<any RadioDirectoryProviding> {
        self { RadioBrowserDirectoryClient() }
            .scope(.singleton)
            .onPreview { PreviewRadioDirectory() }
            .onTest { PreviewRadioDirectory() }
    }
}

/// Registers the app's production directory instance as the shared resolution
/// for ``Container/radioDirectory``. Kept as a free function so callers only need
/// `import RadioDirectory`, not `FactoryKit`, to wire production dependencies.
public func registerProductionRadioDirectory(_ directory: any RadioDirectoryProviding) {
    Container.shared.radioDirectory.register { directory }
}
