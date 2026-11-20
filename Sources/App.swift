import SwiftUI

@main
struct PhotoGatherApp: App {
    private let scan = ScanFolder(dependencies: ScanDependencies(
        library: libraryResources, files: mediaFiles,
        digest: { try Data(fingerprint($0)).base64EncodedString() }, date: captureDate
    ))
    private let importer = ImportSelection {
        let album = try await migrationAlbum()
        return { try await importEntry($0, album: album) }
    }

    var body: some Scene {
        Window("相集 · PhotoGather", id: "main") {
            MigrationView(scan: scan, importer: importer)
        }
    }
}
