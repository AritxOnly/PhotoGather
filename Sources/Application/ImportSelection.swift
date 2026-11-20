import Foundation

struct ImportSelection {
    typealias Writer = (Entry) async throws -> Void
    let prepare: () async throws -> Writer

    @MainActor
    func run(_ entries: [Entry], progress: (URL) -> Void, update: (Int, Entry) -> Void) async throws -> (imported: Int, failed: Int) {
        let indices = entries.indices.filter { entries[$0].selected && entries[$0].verdict.selectable }
        guard !indices.isEmpty else { return (0, 0) }
        let write = try await prepare()
        var imported = 0, failed = 0
        for index in indices {
            var row = entries[index]
            progress(row.url)
            do {
                try await write(row)
                row.verdict = .imported
                imported += 1
            } catch {
                row.verdict = .failed
                row.note = error.localizedDescription
                failed += 1
            }
            row.selected = false
            update(index, row)
        }
        return (imported, failed)
    }
}
