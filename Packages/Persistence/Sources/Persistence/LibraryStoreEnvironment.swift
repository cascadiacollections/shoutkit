import SwiftUI

public extension EnvironmentValues {
    /// The app-wide library store for favorites and recents. `nil` until injected
    /// at the app root, so feature views should guard before mutating.
    @Entry var libraryStore: LibraryStore?
}

public extension View {
    func libraryStore(_ store: LibraryStore) -> some View {
        environment(\.libraryStore, store)
    }
}
