import SwiftUI

/// In-app license display — good FOSS citizenship: the licenses ship with the
/// binary, not just the repo.
struct LicensesView: View {
    var body: some View {
        List {
            Section {
                NavigationLink("ShoutKit App — GPL-3.0") {
                    LicenseTextView(title: "GPL-3.0", resource: "gpl-3.0")
                }
                NavigationLink("Reusable Packages — MIT") {
                    LicenseTextView(title: "MIT", resource: "mit")
                }
            } footer: {
                Text("""
                The app and its feature packages are GPL-3.0; the reusable \
                RadioDirectory, Playback, Persistence, and DesignSystem packages are MIT. \
                The ShoutKit name and icon are trademarks and not covered by these licenses.
                """)
            }

            Section {
                NavigationLink("swift-algorithms — Apache-2.0") {
                    LicenseTextView(title: "Apache-2.0", resource: "apache-2.0")
                }
                NavigationLink("swift-async-algorithms — Apache-2.0") {
                    LicenseTextView(title: "Apache-2.0", resource: "apache-2.0")
                }
                NavigationLink("swift-collections — Apache-2.0") {
                    LicenseTextView(title: "Apache-2.0", resource: "apache-2.0")
                }
                NavigationLink("swift-numerics — Apache-2.0") {
                    LicenseTextView(title: "Apache-2.0", resource: "apache-2.0")
                }
                NavigationLink("Factory — MIT") {
                    LicenseTextView(title: "MIT", resource: "factory-mit")
                }
                NavigationLink("AudioStreaming — MIT") {
                    LicenseTextView(title: "MIT", resource: "audiostreaming-mit")
                }
                NavigationLink("libogg — BSD") {
                    LicenseTextView(title: "BSD", resource: "ogg-bsd")
                }
                NavigationLink("libvorbis — BSD") {
                    LicenseTextView(title: "BSD", resource: "vorbis-bsd")
                }
                // Debug builds link Pulse (never Release — CI symbol-checks
                // that), so builds handed to testers still carry its notice.
                #if DEBUG
                NavigationLink("Pulse (Debug builds only) — MIT") {
                    LicenseTextView(title: "MIT", resource: "pulse-mit")
                }
                #endif
            } header: {
                Text("Third-Party")
            } footer: {
                Text("""
                Apple's swift-algorithms, swift-async-algorithms, \
                swift-collections, and swift-numerics (transitive) packages, \
                Apache-2.0 with the Swift Runtime Library Exception. \
                Factory (hmlongco/Factory) and AudioStreaming (dimitris-c/AudioStreaming), MIT. \
                AudioStreaming's bundled libogg/libvorbis (sbooth's xcframework builds), BSD. \
                Pulse (kean/Pulse), MIT — a debug-only network inspector; its logging never runs \
                in this Release build, though its compiled module may still be present. \
                The full inventory lives in THIRD_PARTY_LICENSES.md in the repository.
                """)
            }
        }
        .navigationTitle("Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LicenseTextView: View {
    let title: String
    let resource: String

    var body: some View {
        ScrollView {
            Text(licenseText)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var licenseText: String {
        guard let url = Bundle.module.url(forResource: resource, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return String(localized: "License text unavailable — see the project repository.", bundle: .module)
        }
        return text
    }
}

#Preview {
    NavigationStack {
        LicensesView()
    }
}
