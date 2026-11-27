import Persistence
import SwiftUI

/// The iCloud sync switch. Its own file for the same reason as
/// `FavoritesBackupSection`: `SettingsView` is near SwiftLint's
/// `type_body_length` limit.
struct ICloudSyncSection: View {
    @Environment(\.settingsStore) private var settings

    var body: some View {
        if let settings {
            Section {
                Toggle(
                    "Sync with iCloud",
                    isOn: Binding(
                        get: { settings.isICloudSyncEnabled },
                        set: { settings.isICloudSyncEnabled = $0 },
                    ),
                )
            } header: {
                Text("iCloud")
            } footer: {
                Text("""
                Keeps your favorites, recently played stations and listening history the same on \
                your devices signed in to iCloud. They are stored in your own iCloud account, where \
                ShoutKit's developer cannot see them. A change here takes effect the next time you \
                open ShoutKit, and turning it off leaves what has already synced in iCloud.
                """)
            }
        }
    }
}
