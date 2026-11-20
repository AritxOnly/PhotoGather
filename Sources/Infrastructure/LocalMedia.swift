import Foundation
import CryptoKit
import ImageIO
import AVFoundation
import UniformTypeIdentifiers

func fingerprint(_ url: URL) throws -> SHA256.Digest {
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    var hash = SHA256()
    while let bytes = try file.read(upToCount: 1024 * 1024), !bytes.isEmpty {
        hash.update(data: bytes)
    }
    return hash.finalize()
}

func captureDate(_ url: URL, video: Bool) async -> Date? {
    if video {
        let asset = AVURLAsset(url: url)
        if let item = try? await asset.load(.creationDate) { return try? await item.load(.dateValue) }
        return nil
    }
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
          let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any],
          let stamp = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String else { return nil }
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.dateFormat = "yyyy:MM:dd HH:mm:ss"
    if let offset = exif["OffsetTimeOriginal"] as? String {
        fmt.dateFormat = "yyyy:MM:dd HH:mm:ssXXXXX"
        return fmt.date(from: stamp + offset)
    }
    return fmt.date(from: stamp)
}

func mediaFiles(in root: URL) throws -> [(URL, Bool)] {
    var enumerationError: Error?
    guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, error in enumerationError = error; return false }) else {
        throw CocoaError(.fileReadUnknown)
    }
    var media = [(URL, Bool)]()
    for case let url as URL in files {
        guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true,
              let type = UTType(filenameExtension: url.pathExtension),
              type.conforms(to: .image) || type.conforms(to: .movie) else { continue }
        media.append((url, type.conforms(to: .movie)))
    }
    if let enumerationError { throw enumerationError }
    return media
}
