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

    /// The persisted-snapshot facet of the directory stack, so landing surfaces can
    /// paint saved stations before (or without) reaching the network. Defaults to the
    /// unavailable cache — previews and tests run against in-memory directories with
    /// nothing on disk — and `AppDependencies.bootstrap()` registers the real one.
    var directoryDiscoveryCache: Factory<any DirectoryDiscoveryCaching> {
        self { UnavailableDirectoryDiscoveryCache() }
            .scope(.singleton)
    }
}

/// Registers the app's production directory instance as the shared resolution
/// for ``Container/radioDirectory``. Kept as a free function so callers only need
/// `import RadioDirectory`, not `FactoryKit`, to wire production dependencies.
public func registerProductionRadioDirectory(_ directory: any RadioDirectoryProviding) {
    Container.shared.radioDirectory.register { directory }
}

/// Registers the app's snapshot-backed directory cache as the shared resolution
/// for ``Container/directoryDiscoveryCache``. Free function for the same reason as
/// ``registerProductionRadioDirectory(_:)``.
public func registerProductionDiscoveryCache(_ cache: any DirectoryDiscoveryCaching) {
    Container.shared.directoryDiscoveryCache.register { cache }
}
