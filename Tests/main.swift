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
