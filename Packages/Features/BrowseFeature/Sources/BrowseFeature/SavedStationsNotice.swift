import BrowseFeatureCore
import Foundation
import RadioDirectory
import SwiftUI

/// A quiet one-line note explaining that the stations on screen aren't live.
///
/// Only shown once a fetch has actually failed. While a saved list is on screen
/// purely because the fetch hasn't finished yet, there's nothing to explain — the
/// list is about to be replaced, and a banner that appears for 200ms and vanishes
/// is worse than no banner.
struct SavedStationsNotice: View {
    let origin: BrowseContentOrigin
    let refreshError: RadioDirectoryError?

    var body: some View {
        if refreshError != nil {
            Label {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "wifi.exclamationmark")
                    .foregroundStyle(.secondary)
            }
            .labelStyle(.titleAndIcon)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(message)
        }
    }

    private var message: String {
        switch origin {
        case let .saved(capturedAt):
            guard let capturedAt else {
                return String(localized: "Offline — showing saved stations.", bundle: .module)
            }
            let updated = capturedAt.formatted(.relative(presentation: .named))
            return String(localized: "Offline — showing stations saved \(updated).", bundle: .module)
        case .live:
            return String(localized: "Couldn't reach the station directory. Showing what's loaded.", bundle: .module)
        }
    }
}

#Preview("Saved") {
    SavedStationsNotice(
        origin: .saved(capturedAt: Date(timeIntervalSinceNow: -3600)),
        refreshError: .transport(nil)
    )
    .padding()
}
