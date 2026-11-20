import AppKit
import SwiftUI

struct LibraryGuide: View {
    @Environment(\.dismiss) private var dismiss
    @State private var launchError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("准备 iCloud 照片").font(.title2.bold()).padding()
            Form {
                Section("在 Mac 上打开 iCloud 照片") {
                    Text("确认 Mac 与 iPhone 使用同一个 Apple 账户。在 Mac 的「照片」中选取「照片」→「设置」→「iCloud」，打开「iCloud 照片」。如果有多个图库，请使用系统照片图库。")
                    Button("打开「照片」…") {
                        Task { await openPhotos() }
                    }
                    if let launchError { Text(launchError).foregroundStyle(.secondary) }
                }
                Section("按需要下载原片") {
                    Text("快速扫描可以保留「优化 Mac 储存空间」。遇到需要核验的云端原件时，相集会联网读取。")
                    Text("准备全库核验时，可以先确认磁盘空间足够，再在同一设置页选择「将原片下载到此 Mac」。整个图库的原始照片和视频都会占用本机空间。")
                    Link("Apple 支持：下载 iCloud 照片和视频", destination: URL(string: "https://support.apple.com/zh-cn/111762")!)
                }
                Section("查看同步进度，再开始扫描") {
                    Text("在「照片」侧栏选择「图库」→「所有照片」，滚动到底部查看同步状态。图库更新后，回到相集选择安卓文件夹。首次扫描时，允许相集完整访问照片图库。")
                    Link("Apple 支持：查看图库状态", destination: URL(string: "https://support.apple.com/zh-cn/119921")!)
                }
            }.formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding()
        }.frame(width: 510, height: 520)
    }

    @MainActor
    private func openPhotos() async {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Photos") else {
            launchError = "请从「应用程序」中打开「照片」。"
            return
        }
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: .init())
            launchError = nil
        } catch {
            launchError = error.localizedDescription
        }
    }
}
