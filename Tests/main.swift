import Foundation

let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: dir) }
let original = dir.appendingPathComponent("original.jpg")
let renamed = dir.appendingPathComponent("renamed.jpg")
var bytes = Data(repeating: 17, count: 2_100_000)
try bytes.write(to: original)
try bytes.write(to: renamed)
let initial = try Data(fingerprint(original))
let same = try Data(fingerprint(renamed))
precondition(initial == same)
bytes[2_099_999] = 18
try bytes.write(to: renamed)
let changed = try Data(fingerprint(renamed))
precondition(initial != changed)
precondition(isScreenshot(URL(fileURLWithPath: "/Android/Pictures/Screenshots/123.png")))
precondition(isScreenshot(URL(fileURLWithPath: "/Pictures/截屏2026.png")))
precondition(!isScreenshot(URL(fileURLWithPath: "/Pictures/Camera/IMG123.jpg")))
precondition(!Verdict.duplicate.selectable && !Verdict.failed.selectable)
print("PASS · 流式哈希、改名副本、末字节变化、截图判断和导入选择")

let resource = LibraryResource(item: LibraryItem(assetID: "asset", filename: "old-name.jpg",
    creationDate: nil, pixelWidth: 100, pixelHeight: 100, video: false), digest: { initial.base64EncodedString() })
let scanner = ScanFolder(dependencies: ScanDependencies(library: { [resource] },
    files: { _ in [(original, false), (renamed, false)] },
    digest: { try Data(fingerprint($0)).base64EncodedString() }, date: { _, _ in nil }))
let quick = try await scanner(dir, exhaustive: false) { _ in }
let full = try await scanner(dir, exhaustive: true) { _ in }
precondition(quick.map(\.verdict) == [.fresh, .fresh])
precondition(full.map(\.verdict) == [.duplicate, .fresh])
precondition(full.map(\.selected) == [false, true])
let screenshot = URL(fileURLWithPath: "/Screenshots/example.png")
precondition(classify(url: screenshot, exact: true, hasCandidate: true) == .duplicate)
precondition(classify(url: screenshot, exact: false, hasCandidate: true) == .screenshot)

var selection = full
selection[0].selected = true
var failedRow = Entry(url: dir)
failedRow.verdict = .fresh
failedRow.selected = true
selection.insert(failedRow, at: 1)
let workflow = ImportSelection { { row in
    precondition(row.verdict.selectable)
    if row.url == dir { throw CocoaError(.fileReadUnknown) }
} }
var updated = selection
let counts = try await workflow.run(selection, progress: { _ in }) { updated[$0] = $1 }
precondition(counts == (1, 1))
precondition(updated.map(\.verdict) == [.duplicate, .failed, .imported])
print("PASS · 快速与全库扫描、判定优先级、导入守卫和单项失败后继续")
