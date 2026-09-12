import Persistence
import SwiftUI
import UniformTypeIdentifiers

/// Favorites export/import, split out of `SettingsView` so the transfer state,
/// its file-presentation modifiers, and the JSON plumbing sit with the one
/// section that uses them. `SettingsView` had grown past SwiftLint's
/// `type_body_length` limit, and this is the seam that was already there — the
/// state is used by nothing else in Settings.
struct FavoritesBackupSection: View {
    @Environment(\.libraryStore) private var library
    @State private var exportFile: FavoritesExportFile?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var alertMessage: String?
    @State private var isShowingAlert = false

    var body: some View {
        Section {
            Button("Export Favorites", systemImage: "square.and.arrow.up") {
                startExport()
            }
            Button("Import Favorites", systemImage: "square.and.arrow.down") {
                isImporting = true
            }
        } header: {
            Text("Favorites Backup")
        } footer: {
            Text("""
            Export and import favorites as a plain JSON file. Recents and recently heard tracks are \
            intentionally not included. Import merges by station ID: existing favorites keep their \
            order, and new favorites append at the end.
            """)
        }
        .disabled(library == nil)
        .fileExporter(
            isPresented: $isExporting,
            document: exportFile,
            contentType: .json,
            defaultFilename: "shoutkit-favorites",
        ) { result in
            if case let .failure(error) = result {
                presentAlert(error.localizedDescription)
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
        ) { result in
            handleImport(result)
        }
        .alert("Favorites", isPresented: $isShowingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "An unknown error occurred.")
        }
    }

    private func startExport() {
        guard let library else {
            presentAlert("Favorites storage is unavailable right now.")
            return
        }
        do {
            exportFile = try FavoritesExportFile(data: library.exportFavoritesJSONData())
            isExporting = true
        } catch {
            presentAlert(error.localizedDescription)
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard let library else {
            presentAlert("Favorites storage is unavailable right now.")
            return
        }

        switch result {
        case let .success(url):
            do {
                let data = try readImportedFileData(from: url)
                let importResult = try library.importFavoritesJSONData(data)
                if importResult.addedCount == 0 {
                    presentAlert("No new favorites were imported.")
                } else {
                    presentAlert(
                        "Imported \(importResult.addedCount) favorite\(importResult.addedCount == 1 ? "" : "s").",
                    )
                }
            } catch {
                presentAlert(error.localizedDescription)
            }
        case let .failure(error):
            presentAlert(error.localizedDescription)
        }
    }

    private func readImportedFileData(from url: URL) throws -> Data {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try Data(contentsOf: url)
    }

    private func presentAlert(_ message: String) {
        alertMessage = message
        isShowingAlert = true
    }
}

private struct FavoritesExportFile: FileDocument {
    static var readableContentTypes: [UTType] {
        [.json]
    }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
