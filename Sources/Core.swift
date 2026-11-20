import Foundation
import CryptoKit

func fingerprint(_ url: URL) throws -> SHA256.Digest {
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    var hash = SHA256()
    while let bytes = try file.read(upToCount: 1024 * 1024), !bytes.isEmpty {
        hash.update(data: bytes)
    }
    return hash.finalize()
}

func isScreenshot(_ url: URL) -> Bool {
    let markers = ["screenshot", "screen_shot", "screen shot", "截屏", "截图"]
    return url.pathComponents.contains { component in
        markers.contains { component.lowercased().hasPrefix($0) }
    }
}

enum Verdict: String {
    case fresh = "未找到匹配", duplicate = "完全重复", review = "疑似同一内容"
    case screenshot = "疑似截图", failed = "待核验", imported = "已导入"
    var selectable: Bool { [.fresh, .review, .screenshot].contains(self) }
}
