import Foundation

struct LibraryResource {
    let item: LibraryItem
    let digest: () async throws -> String
}

struct ScanDependencies {
    var library: () async throws -> [LibraryResource]
    var files: (URL) throws -> [(URL, Bool)]
    var digest: (URL) throws -> String
    var date: (URL, Bool) async -> Date?
}

struct ScanFolder {
    let dependencies: ScanDependencies
    func callAsFunction(_ root: URL, exhaustive: Bool, progress: @escaping @Sendable (String) -> Void) async throws -> [Entry] {
        var names = [String: [Int]](), times = [Int: [Int]]()
        let resources = try await dependencies.library()
        for (index, resource) in resources.enumerated() {
            let item = resource.item
            names[item.filename.lowercased(), default: []].append(index)
            if let date = item.creationDate { times[Int(date.timeIntervalSince1970), default: []].append(index) }
        }
        var rows = [Entry](), seen = [String: URL](), cache = [Int: String]()
        var exact = [String: Int]()
        if exhaustive {
            for group in names.values {
                for candidate in group {
                    progress("正在核验图库原件 · " + resources[candidate].item.filename)
                    let hash = try await resources[candidate].digest()
                    cache[candidate] = hash
                    exact[hash] = candidate
                }
            }
        }
        for (url, video) in try dependencies.files(root) {
            progress("正在核验第 \(rows.count + 1) 项 · \(url.lastPathComponent)")
            var row = Entry(url: url)
            do {
                row.digest = try dependencies.digest(url)
                if let first = seen[row.digest] {
                    row.verdict = .duplicate
                    row.note = "文件夹内与 \(first.path) 相同"
                } else {
                    row.date = await dependencies.date(url, video)
                    var candidates = names[url.lastPathComponent.lowercased()] ?? []
                    if let date = row.date {
                        let t = Int(date.timeIntervalSince1970)
                        for second in (t-1)...(t+1) { candidates += times[second] ?? [] }
                    }
                    if let match = exact[row.digest] { candidates.insert(match, at: 0) }
                    var checked = Set<Int>()
                    var matched = false
                    for c in candidates where resources[c].item.video == video && checked.insert(c).inserted {
                        let hash: String
                        if let value = cache[c] { hash = value }
                        else { hash = try await resources[c].digest(); cache[c] = hash }
                        row.peer = resources[c].item
                        row.note = resources[c].item.filename
                        if row.digest == hash { matched = true; break }
                    }
                    row.verdict = classify(url: url, exact: matched, hasCandidate: row.peer != nil)
                    row.selected = row.verdict == .fresh
                    seen[row.digest] = url
                }
            } catch { row.verdict = .failed; row.note = error.localizedDescription }
            rows.append(row)
        }
        return rows
    }

}
