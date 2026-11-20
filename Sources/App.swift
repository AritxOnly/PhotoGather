import SwiftUI
import Photos
import AVFoundation
import ImageIO

@main
struct PhotoGatherApp: App {
    var body: some Scene {
        Window("相集 · PhotoGather", id: "main") { MigrationView() }
    }
}

struct PreviewPanel: View {
    let row: Entry
    @State private var local: NSImage?
    @State private var remote: NSImage?
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                tile("安卓文件", local)
                if row.peer != nil { tile("图库候选", remote) }
            }
            Text(row.url.path).font(.caption).textSelection(.enabled)
            if let date = row.date { Text("文件拍摄时间 " + date.formatted()).font(.caption) }
            if let peer = row.peer {
                let dimensions = "\(peer.pixelWidth) × \(peer.pixelHeight)"
                let date = peer.creationDate?.formatted() ?? ""
                Text("图库候选  \(dimensions)  \(date)").font(.caption)
            }
            if !row.note.isEmpty { Text(row.note).font(.caption).textSelection(.enabled) }
        }
        .task(id: row.id) {
            local = nil
            remote = nil
            let url = row.url
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
            guard !Task.isCancelled else { return }
            local = img.map { NSImage(cgImage: $0, size: .zero) }
            if let asset = row.peer {
                let opts = PHImageRequestOptions()
                opts.deliveryMode = .highQualityFormat
                opts.isNetworkAccessAllowed = true
                let thumb: NSImage? = await withCheckedContinuation { resume in
                    PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 600, height: 400), contentMode: .aspectFit, options: opts) { image, info in
                        if info?[PHImageResultIsDegradedKey] as? Bool != true { resume.resume(returning: image) }
                    }
                }
                if !Task.isCancelled { remote = thumb }
            }
        }
    }
    func tile(_ title: String, _ image: NSImage?) -> some View {
        VStack {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "photo").foregroundStyle(.secondary) }
            Text(title).font(.caption)
        }.frame(maxWidth: .infinity).frame(height: 150)
    }
}

struct MigrationView: View {
    @State private var rows = [Entry]()
    @State private var status = "选择安卓照片和视频所在的文件夹。"
    @State private var exhaustive = false
    @State private var busy = false
    @State private var focused: URL?
    @State private var filter: Verdict?
    @State private var confirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("选择文件夹并扫描…", action: choose)
                Picker("显示", selection: $filter) {
                    Text("全部").tag(nil as Verdict?)
                    ForEach([Verdict.fresh, .screenshot, .review, .duplicate, .failed, .imported], id: \.self) { v in Text(v.rawValue).tag(Optional(v)) }
                }.frame(width: 190)
                Spacer()
                Button("导入所选 \(rows.filter(\.selected).count) 项") { confirm = true }
                    .disabled(!rows.contains(where: \.selected))
            }.disabled(busy)
            Toggle("全库原件核验（可能下载整个 iCloud 图库）", isOn: $exhaustive).disabled(busy)
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Text(status).lineLimit(2).foregroundStyle(.secondary)
            }
            List(selection: $focused) {
                ForEach($rows) { $row in
                    if filter == nil || row.verdict == filter {
                        HStack {
                            Toggle("选择", isOn: $row.selected).labelsHidden().disabled(busy || !row.verdict.selectable)
                            Text(row.url.lastPathComponent)
                            Spacer()
                            Text(row.verdict.rawValue).foregroundStyle(.secondary)
                        }.tag(row.id)
                    }
                }
            }
            if let row = rows.first(where: { $0.id == focused }) { PreviewPanel(row: row) }
        }.padding().frame(minWidth: 680, minHeight: 490)
        .alert("将所选项目导入系统照片图库？", isPresented: $confirm) {
            Button("取消", role: .cancel) {}
            Button("导入") { Task { await runImport() } }
        } message: { Text("照片和视频将加入「安卓迁移」相簿，并按系统的 iCloud 照片设置同步。") }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        rows = []; focused = nil; filter = nil; busy = true
        status = "正在读取系统照片图库…"
        Task {
            defer { busy = false }
            do {
                rows = try await scan(url, exhaustive: exhaustive) { message in
                    DispatchQueue.main.async { status = message }
                }
                status = "扫描完成，共 \(rows.count) 项。请核对所选内容后导入。"
            } catch { status = error.localizedDescription }
        }
    }

    private func runImport() async {
        busy = true
        defer { busy = false }
        var imported = 0, failed = 0
        do {
            let album = try await migrationAlbum()
            for index in rows.indices where rows[index].selected {
                status = "正在导入 \(rows[index].url.lastPathComponent)"
                do {
                    try await importEntry(rows[index], album: album)
                    rows[index].verdict = .imported
                    imported += 1
                } catch {
                    rows[index].verdict = .failed
                    rows[index].note = error.localizedDescription
                    failed += 1
                }
                rows[index].selected = false
            }
            status = "已导入 \(imported) 项，失败 \(failed) 项。iCloud 同步进度可在「照片」中查看。"
        } catch { status = error.localizedDescription }
    }
}
