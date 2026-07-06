import SwiftUI

public extension EnvironmentValues {
    /// The app-wide settings store. `nil` until injected at the root.
    @Entry var settingsStore: SettingsStore?
}

public extension View {
    func settingsStore(_ store: SettingsStore) -> some View {
        environment(\.settingsStore, store)
    }
}
