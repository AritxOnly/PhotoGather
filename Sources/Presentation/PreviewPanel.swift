import SwiftUI

struct PreviewPanel: View {
    let row: Entry
    let samplePeer: URL?
    @State private var local: NSImage?
    @State private var remote: NSImage?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(row.url.lastPathComponent).font(.title3.weight(.semibold)).textSelection(.enabled)
                Label(row.verdict.rawValue, systemImage: row.verdict.icon)
                    .font(.callout).foregroundStyle(row.verdict.tint)
                tile("安卓文件", local)
                if row.peer != nil { tile("图库候选", remote) }
                Divider()
                if let date = row.date { LabeledContent("拍摄时间", value: date.formatted()) }
                if let peer = row.peer {
                    LabeledContent("图库尺寸", value: "\(peer.pixelWidth) × \(peer.pixelHeight)")
                    if let date = peer.creationDate { LabeledContent("图库日期", value: date.formatted()) }
                }
                if !row.note.isEmpty { Text(row.note).textSelection(.enabled) }
                if samplePeer == nil { Text(row.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding()
        }
        .task(id: row.id) {
            local = nil
            remote = nil
            let image = await Thumbnails.local(row.url)
            guard !Task.isCancelled else { return }
            local = image
            if let peer = row.peer {
                let thumb: NSImage?
                if let samplePeer { thumb = await Thumbnails.local(samplePeer) }
                else { thumb = await Thumbnails.library(peer.assetID) }
                if !Task.isCancelled { remote = thumb }
            }
        }
    }
    func tile(_ title: String, _ image: NSImage?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                if let image { Image(nsImage: image).resizable().scaledToFit() }
                else { Image(systemName: "photo").foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity).frame(height: 160).clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
