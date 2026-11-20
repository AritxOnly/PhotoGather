import Foundation

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

struct LibraryItem {
    let assetID: String
    let filename: String
    let creationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let video: Bool
}
struct Entry: Identifiable {
    var id: URL { url }
    let url: URL
    var digest = ""
    var verdict = Verdict.failed
    var note = ""
    var peer: LibraryItem?
    var date: Date?
    var selected = false
}


func classify(url: URL, exact: Bool, hasCandidate: Bool) -> Verdict {
    if exact { return .duplicate }
    if isScreenshot(url) { return .screenshot }
    return hasCandidate ? .review : .fresh
}
