import RadioDirectory
import SwiftUI

/// The one "couldn't reach the directory" state, shared by every surface that
/// can hit one.
///
/// Listen Now, Search, and the genre strip each grew their own
/// `ContentUnavailableView` with the same icon, the same layout, and slightly
/// different minimum heights — so the same failure looked like three different
/// failures depending on where you were standing. `Try Again` appears only for
/// retryable errors: offering a retry that is guaranteed to fail the same way
/// (a parse or config error) trains people to ignore the button.
public struct DirectoryUnavailableView: View {
    private let title: String
    private let error: RadioDirectoryError
    private let minHeight: CGFloat
    private let retry: () -> Void

    public init(
        title: String,
        error: RadioDirectoryError,
        minHeight: CGFloat = 240,
        retry: @escaping () -> Void
    ) {
        self.title = title
        self.error = error
        self.minHeight = minHeight
        self.retry = retry
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "wifi.exclamationmark")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            if error.isRetryable {
                // `String(localized:bundle:)`, not a bare literal: a
                // `LocalizedStringKey` in a package resolves against
                // `Bundle.main`, so this module's catalog entry would never be
                // consulted and the button would sit in English forever.
                Button(String(localized: "Try Again", bundle: .module), action: retry)
                    .buttonStyle(.glassProminent)
            }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
    }
}

#Preview {
    DirectoryUnavailableView(title: "Directory Unavailable", error: .transport(nil), retry: {})
        .tint(.shoutKitAccent)
}
