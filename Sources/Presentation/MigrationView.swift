import SwiftUI

struct MigrationView: View {
    let scan: ScanFolder
    let importer: ImportSelection
    @State private var sample: DemoSession?
    private var demo: Bool { sample != nil }
    @State private var rows = [Entry]()
    @State private var status = "选择安卓照片和视频所在的文件夹。"
    @State private var exhaustive = false
    @State private var busy = false
    @State private var focused: URL?
    private enum Category: Hashable {
        case all, verdict(Verdict)
    }

    @State private var category: Category? = .all
    @State private var showingGuide = false
    private var filter: Verdict? {
        if case let .verdict(value) = category { return value }
        return nil
    }
    @State private var confirm = false

    @State private var folderName = ""

    private var visibleRows: [Entry] { rows.filter { filter == nil || $0.verdict == filter } }
    private var selectedCount: Int { rows.filter(\.selected).count }

    var body: some View {
        NavigationSplitView {
            List(selection: $category) {
                Section("迁移清单") {
                    Label("全部文件", systemImage: "photo.stack")
                        .badge(rows.count).tag(Category.all)
                    ForEach([Verdict.fresh, .duplicate, .review, .screenshot, .failed, .imported], id: \.self) { verdict in
                        Label(verdict.rawValue, systemImage: verdict.icon)
                            .badge(rows.filter { $0.verdict == verdict }.count)
                            .tag(Category.verdict(verdict))
                    }
                }
            }.listStyle(.sidebar)
            .onChange(of: category) { _ in focused = visibleRows.first?.id }
            .navigationSplitViewColumnWidth(min: 170, ideal: 185, max: 230)
            .safeAreaInset(edge: .bottom) {
                Toggle("全库原件核验", isOn: $exhaustive)
                    .toggleStyle(.switch).controlSize(.small).disabled(busy)
                    .help("下次扫描时核验所有可访问的图库原件，可能下载整个 iCloud 图库。")
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
            }
        } detail: {
            if rows.isEmpty && !busy && folderName.isEmpty {
                VStack(spacing: 18) {
                    Image(systemName: "photo.stack.fill").font(.system(size: 56, weight: .light))
                        .symbolRenderingMode(.hierarchical).foregroundStyle(Color.accentColor)
                    Text("把安卓照片带回相册").font(.largeTitle.weight(.semibold))
                    Text("先比对重复项目和截图，再将选中的原件加入「照片」。")
                        .foregroundStyle(.secondary)
                    Button("如何准备 iCloud 照片？") { showingGuide = true }.buttonStyle(.link)
                    HStack {
                        Button("选择文件夹…", action: choose).buttonStyle(.borderedProminent)
                        Button("体验示例", action: loadDemo)
                    }.controlSize(.large)
                }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(filter?.rawValue ?? "全部文件").font(.title.weight(.semibold))
                            Text("\(visibleRows.count) 个项目 · 已勾选 \(selectedCount) 个")
                                .font(.callout).foregroundStyle(.secondary)
                        }.padding()
                        Divider()
                        if visibleRows.isEmpty {
                            Text(busy ? "正在扫描…" : "这里没有项目")
                                .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            List(selection: $focused) {
                                ForEach($rows) { $row in
                                    if filter == nil || row.verdict == filter {
                                        HStack(spacing: 10) {
                                            Toggle("选择 " + row.url.lastPathComponent, isOn: $row.selected)
                                                .labelsHidden().disabled(busy || !row.verdict.selectable)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(row.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                                Label(row.verdict.rawValue, systemImage: row.verdict.icon)
                                                    .font(.caption).foregroundStyle(row.verdict.tint)
                                            }
                                        }.padding(.vertical, 4).tag(row.id)
                                    }
                                }
                            }.listStyle(.inset)
                        }
                    }.frame(minWidth: 245, idealWidth: 350, maxHeight: .infinity)
                    Group {
                        if let row = visibleRows.first(where: { $0.id == focused }) {
                            PreviewPanel(row: row, samplePeer: sample?.libraryPreview)
                        } else {
                            Label("选择文件以预览", systemImage: "photo.on.rectangle")
                                .foregroundStyle(.secondary)
                        }
                    }.frame(minWidth: 260, idealWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle(folderName.isEmpty ? "相集" : folderName)
        .toolbar {
            ToolbarItemGroup {
                Button { showingGuide = true } label: {
                    Label("iCloud 照片准备指南", systemImage: "questionmark.circle")
                }.help("查看 iCloud 照片准备指南")
                Button(action: choose) { Label("选择文件夹", systemImage: "folder.badge.plus") }
                    .help("选择安卓照片文件夹并扫描").disabled(busy)
                Button(action: loadDemo) { Label("体验示例", systemImage: "play.rectangle") }
                    .help("体验内置示例").disabled(busy)
                Button { confirm = true } label: {
                    Label(demo ? "演练导入 \(selectedCount) 项" : "导入 \(selectedCount) 项", systemImage: "square.and.arrow.down")
                }.buttonStyle(.borderedProminent).disabled(busy || selectedCount == 0)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 8) {
                if busy { ProgressView().controlSize(.small) }
                else { Image(systemName: demo ? "play.rectangle" : "info.circle") }
                Text(status).lineLimit(2)
                Spacer()
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.vertical, 8)
                .background(.bar)
        }
        .frame(minWidth: 800, minHeight: 480)
        .sheet(isPresented: $showingGuide) { LibraryGuide() }
        .alert(demo ? "演练导入所选示例？" : "将所选项目导入系统照片图库？", isPresented: $confirm) {
            Button("取消", role: .cancel) {}
            Button(demo ? "演练导入" : "导入") { Task { await runImport() } }
        } message: {
            Text(demo ? "示例只更新本窗口中的结果。" : "照片和视频将加入「安卓迁移」相簿，并按系统的 iCloud 照片设置同步。")
        }
    }

    private func loadDemo() {
        do {
            let session = try DemoSession()
            sample = session
            folderName = "示例照片"
            busy = true
            category = .all
            focused = nil
            rows = []
            status = "正在扫描示例…"
            Task {
                defer { busy = false }
                do {
                    rows = try await session.scan(session.root, exhaustive: exhaustive) { _ in }
                    focused = rows.first?.id
                    status = "示例模式 · 可预览、筛选并演练导入。"
                } catch { status = error.localizedDescription }
            }
        } catch { status = error.localizedDescription }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        sample = nil
        folderName = url.lastPathComponent
        rows = []; focused = nil; category = .all; busy = true
        status = "正在读取系统照片图库…"
        Task {
            defer { busy = false }
            do {
                rows = try await scan(url, exhaustive: exhaustive) { message in
                    DispatchQueue.main.async { status = message }
                }
                focused = rows.first?.id
                status = "扫描完成，共 \(rows.count) 项。请核对所选内容后导入。"
            } catch { status = error.localizedDescription }
        }
    }

    private func runImport() async {
        busy = true
        defer { busy = false }
        do {
            let workflow = demo ? DemoSession.importer : importer
            let counts = try await workflow.run(rows, progress: { status = "正在导入 " + $0.lastPathComponent }) { index, row in
                rows[index] = row
            }
            status = (demo ? "示例演练 · " : "") + "已导入 \(counts.imported) 项，失败 \(counts.failed) 项。" + (demo ? "" : "iCloud 同步进度可在「照片」中查看。")
        } catch { status = error.localizedDescription }
    }
}
