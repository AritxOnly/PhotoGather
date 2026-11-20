import Photos
import CryptoKit
import UniformTypeIdentifiers

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

func libraryResources() async throws -> [LibraryResource] {
    guard await PHPhotoLibrary.requestAuthorization(for: .readWrite) == .authorized else {
        throw NSError(domain: "PhotoGather", code: 1, userInfo: [NSLocalizedDescriptionKey: "请在系统设置中允许 PhotoGather 完整访问照片图库。"])
    }
    var resources = [LibraryResource]()
    PHAsset.fetchAssets(with: nil).enumerateObjects { asset, _, _ in
        for resource in PHAssetResource.assetResources(for: asset) where [.photo, .video, .alternatePhoto].contains(resource.type) {
            let item = LibraryItem(assetID: asset.localIdentifier, filename: resource.originalFilename,
                                   creationDate: asset.creationDate, pixelWidth: asset.pixelWidth,
                                   pixelHeight: asset.pixelHeight, video: asset.mediaType == .video)
            resources.append(LibraryResource(item: item, digest: { try await assetDigest(resource) }))
        }
    }
    return resources
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
