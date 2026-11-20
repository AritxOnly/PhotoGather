import AppKit
import Photos
import CryptoKit
import UniformTypeIdentifiers
import ImageIO
import AVFoundation

struct Entry: Identifiable {
    var id: URL { url }
    let url: URL
    var digest = ""
    var verdict = Verdict.failed
    var note = ""
    var peer: PHAsset?
    var date: Date?
    var selected = false
}

private struct Candidate {
    let asset: PHAsset
    let resource: PHAssetResource
}

private func assetDigest(_ resource: PHAssetResource) async throws -> String {
    let options = PHAssetResourceRequestOptions()
    options.isNetworkAccessAllowed = true
    return try await withCheckedThrowingContinuation { continuation in
        var hash = SHA256()
        PHAssetResourceManager.default().requestData(for: resource, options: options) {
            hash.update(data: $0)
        } completionHandler: { error in
            if let error { continuation.resume(throwing: error) }
            else { continuation.resume(returning: Data(hash.finalize()).base64EncodedString()) }
        }
    }
}

private func captureDate(_ url: URL, video: Bool) async -> Date? {
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

private func mediaFiles(in root: URL) throws -> [(URL, UTType)] {
    var enumerationError: Error?
    guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, error in enumerationError = error; return false }) else {
        throw CocoaError(.fileReadUnknown)
    }
    var media = [(URL, UTType)]()
    for case let url as URL in files {
        guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true,
              let type = UTType(filenameExtension: url.pathExtension),
              type.conforms(to: .image) || type.conforms(to: .movie) else { continue }
        media.append((url, type))
    }
    if let enumerationError { throw enumerationError }
    return media
}

func scan(_ root: URL, exhaustive: Bool, progress: @escaping @Sendable (String) -> Void) async throws -> [Entry] {
    guard await PHPhotoLibrary.requestAuthorization(for: .readWrite) == .authorized else {
        throw NSError(domain: "PhotoGather", code: 1, userInfo: [NSLocalizedDescriptionKey: "请在系统设置中允许 PhotoGather 完整访问照片图库。"])
    }
    var names = [String: [Candidate]](), times = [Int: [Candidate]]()
    PHAsset.fetchAssets(with: nil).enumerateObjects { asset, _, _ in
        for resource in PHAssetResource.assetResources(for: asset) where [.photo, .video, .alternatePhoto].contains(resource.type) {
            let candidate = Candidate(asset: asset, resource: resource)
            names[resource.originalFilename.lowercased(), default: []].append(candidate)
            if let date = asset.creationDate { times[Int(date.timeIntervalSince1970), default: []].append(candidate) }
        }
    }
    var rows = [Entry](), seen = [String: URL](), cache = [ObjectIdentifier: String]()
    var exact = [String: Candidate]()
    if exhaustive {
        for group in names.values {
            for candidate in group {
                progress("正在核验图库原件 · " + candidate.resource.originalFilename)
                let hash = try await assetDigest(candidate.resource)
                cache[ObjectIdentifier(candidate.resource)] = hash
                exact[hash] = candidate
            }
        }
    }
    for (url, type) in try mediaFiles(in: root) {
        progress("正在核验第 \(rows.count + 1) 项 · \(url.lastPathComponent)")
        var row = Entry(url: url)
        do {
            row.digest = try Data(fingerprint(url)).base64EncodedString()
            if let first = seen[row.digest] {
                row.verdict = .duplicate
                row.note = "文件夹内与 \(first.path) 相同"
            } else {
                let video = type.conforms(to: .movie)
                row.date = await captureDate(url, video: video)
                var candidates = names[url.lastPathComponent.lowercased()] ?? []
                if let date = row.date {
                    let t = Int(date.timeIntervalSince1970)
                    for second in (t-1)...(t+1) { candidates += times[second] ?? [] }
                }
                if let match = exact[row.digest] { candidates.insert(match, at: 0) }
                var checked = Set<ObjectIdentifier>()
                row.verdict = .fresh
                for c in candidates where (c.asset.mediaType == .video) == video && checked.insert(ObjectIdentifier(c.resource)).inserted {
                    let key = ObjectIdentifier(c.resource)
                    let hash: String
                    if let value = cache[key] { hash = value }
                    else { hash = try await assetDigest(c.resource); cache[key] = hash }
                    row.peer = c.asset
                    row.note = c.resource.originalFilename
                    if row.digest == hash { row.verdict = .duplicate; break }
                    row.verdict = .review
                }
                if isScreenshot(url), row.verdict != .duplicate { row.verdict = .screenshot }
                row.selected = row.verdict == .fresh
                seen[row.digest] = url
            }
        } catch { row.verdict = .failed; row.note = error.localizedDescription }
        rows.append(row)
    }
    return rows
}

func importEntry(_ row: Entry, album: PHAssetCollection) async throws {
    let fm = FileManager.default
    let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: temp, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: temp) }
    let copy = temp.appendingPathComponent(row.url.lastPathComponent)
    try fm.copyItem(at: row.url, to: copy)
    guard try Data(fingerprint(copy)).base64EncodedString() == row.digest else {
        throw NSError(domain: "PhotoGather", code: 2, userInfo: [NSLocalizedDescriptionKey: "文件已改变，请重新扫描。"])
    }
    let movie = UTType(filenameExtension: copy.pathExtension)?.conforms(to: .movie) == true
    var assetID: String?
    try await PHPhotoLibrary.shared().performChanges {
        guard let collection = PHAssetCollectionChangeRequest(for: album) else { return }
        let request = PHAssetCreationRequest.forAsset()
        request.addResource(with: movie ? .video : .photo, fileURL: copy, options: nil)
        if let date = row.date { request.creationDate = date }
        if let item = request.placeholderForCreatedAsset {
            assetID = item.localIdentifier
            collection.addAssets([item] as NSArray)
        }
    }
    guard assetID != nil else { throw CocoaError(.fileWriteUnknown) }
}

func migrationAlbum() async throws -> PHAssetCollection {
    let options = PHFetchOptions()
    options.predicate = NSPredicate(format: "title == %@", "安卓迁移")
    if let album = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: options).firstObject { return album }
    try await PHPhotoLibrary.shared().performChanges {
        PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: "安卓迁移")
    }
    guard let album = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: options).firstObject else { throw CocoaError(.fileWriteUnknown) }
    return album
}
