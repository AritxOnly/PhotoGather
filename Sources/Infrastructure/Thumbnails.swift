import AppKit
import AVFoundation
import ImageIO
import Photos

struct Thumbnails {
    static func local(_ url: URL) async -> NSImage? {
        let img = await Task.detached { () -> CGImage? in
            if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
               let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 600
               ] as CFDictionary) { return cg }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 600, height: 400)
            guard let frame = try? await generator.image(at: .zero) else { return nil }
            return frame.image
        }.value
        return img.map { NSImage(cgImage: $0, size: .zero) }
    }

    static func library(_ id: String) async -> NSImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .highQualityFormat
        opts.isNetworkAccessAllowed = true
        let thumb: NSImage? = await withCheckedContinuation { resume in
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 600, height: 400), contentMode: .aspectFit, options: opts) { image, info in
                if info?[PHImageResultIsDegradedKey] as? Bool != true { resume.resume(returning: image) }
            }
        }
        return thumb
    }
}
