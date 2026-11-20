import AppKit

/// A private set of media files for one preview session.
final class DemoSession {
    let root: URL
    let scan: ScanFolder
    let libraryPreview: URL

    static let importer = ImportSelection { { _ in } }

    init() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.root = root
        let coast = root.appendingPathComponent("海边.png")
        let copy = root.appendingPathComponent("海边副本.png")
        let sunset = root.appendingPathComponent("落日.png")
        let screen = root.appendingPathComponent("Screenshot_行程.png")
        libraryPreview = coast
        do {
            try Self.draw(coast, sky: .systemTeal, land: .systemBlue, symbol: "sailboat.fill")
            try FileManager.default.copyItem(at: coast, to: copy)
            try Self.draw(sunset, sky: .systemOrange, land: .systemIndigo, symbol: "sun.horizon.fill")
            try Self.draw(screen, sky: .systemGray, land: .darkGray, symbol: "calendar")
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
        let item = LibraryItem(assetID: "demo", filename: sunset.lastPathComponent, creationDate: nil,
                               pixelWidth: 720, pixelHeight: 480, video: false)
        scan = ScanFolder(dependencies: ScanDependencies(
            library: { [LibraryResource(item: item, digest: { try Data(fingerprint(coast)).base64EncodedString() })] },
            files: { _ in [coast, copy, sunset, screen].map { ($0, false) } },
            digest: { try Data(fingerprint($0)).base64EncodedString() }, date: { _, _ in nil }
        ))
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    private static func draw(_ url: URL, sky: NSColor, land: NSColor, symbol: String) throws {
        let size = NSSize(width: 720, height: 480)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(starting: sky, ending: land)?.draw(in: rect, angle: -80)
            let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            icon?.draw(in: NSRect(x: 252, y: 132, width: 216, height: 216))
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
    }
}
