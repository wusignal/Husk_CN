// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UniformTypeIdentifiers

/// 从其他 App 分享到 Husk 的 APK：分享面板中的“Husk”（或“拷贝到 Husk”），或从“文件”中选择“在 Husk 中打开”。
///
/// 每个到来的 URL 可能只在片刻内可读（其他 App 容器中带安全域的文件，或 iOS 在 Documents/Inbox 中生成的副本），
/// 因此立即复制到 Husk 自己的文件夹，然后询问用户放到哪里：翻译层——直接在 iPhone 上运行游戏——或 Android。
/// 一次分享多个（基础 APK 及其分片）时，URL 一个接一个到达，会被汇总成一次询问。
@MainActor
final class IncomingFiles: ObservableObject {
    static let shared = IncomingFiles()

    /// 等待用户选择去向的文件。
    @Published var waiting: [URL] = []
    /// 发给 Android 的文件，暂存直到 Android 就绪接收。
    @Published private(set) var forAndroid: [URL] = []

    private var gathering: [URL] = []
    private var gatherTask: Task<Void, Never>?

    /// 副本暂存处。Husk 启动时清空，避免残留占用空间。
    nonisolated static var folder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Incoming", isDirectory: true)
    }

    nonisolated static func clearLeftovers() {
        try? FileManager.default.removeItem(at: folder)
    }

    static let extensions: Set<String> = ["apk", "xapk", "apkm", "apks"]

    /// 正在复制中，用一行字告知。
    @Published private(set) var preparing: String?

    /// iOS 用某个 URL 打开了 Husk。非 APK 或其整包的内容一律忽略（husk:// 链接不是文件）。
    func receive(_ url: URL) {
        guard url.isFileURL, Self.extensions.contains(url.pathExtension.lowercased()) else { return }
        take([url]) { copies in
            self.gathering += copies
            // 拆分包的分片一个接一个到达：全部到齐后询问一次。
            self.gatherTask?.cancel()
            self.gatherTask = Task {
                try? await Task.sleep(nanoseconds: 600_000_000)
                guard !Task.isCancelled else { return }
                self.waiting += self.gathering
                self.gathering = []
            }
        }
    }

    /// 在 Husk 内部选择的文件：一次性全部到达，因此是一次询问。
    func receive(_ urls: [URL]) {
        let wanted = urls.filter { Self.extensions.contains($0.pathExtension.lowercased()) }
        guard !wanted.isEmpty else { return }
        take(wanted) { self.waiting += $0 }
    }

    /// 把文件复制到 Husk 自己的文件夹（后台线程——游戏可能有几个 GB），然后交回复本。
    private func take(_ urls: [URL], then: @escaping @MainActor ([URL]) -> Void) {
        preparing = urls.count == 1 ? "正在准备 \(urls[0].lastPathComponent)…" : "正在准备 \(urls.count) 个文件…"
        Task.detached(priority: .userInitiated) {
            var copies: [URL] = []
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let dir = Self.folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
                let copy = dir.appendingPathComponent(url.lastPathComponent)
                do {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: copy)
                    copies.append(copy)
                    // iOS 自己的副本（Documents/Inbox）在 Husk 已有副本后就没用了。
                    if url.path.contains("/Documents/Inbox/") { try? FileManager.default.removeItem(at: url) }
                    HuskLog.log("ui", "took in \(url.lastPathComponent)")
                } catch {
                    HuskLog.log("ui", "could not take in \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            await MainActor.run {
                self.preparing = nil
                if !copies.isEmpty { then(copies) }
            }
        }
    }

    /// 在 iPhone 本机运行（翻译层）。
    func sendToTranslationLayer() {
        let urls = waiting
        waiting = []
        guard !urls.isEmpty else { return }
        // 移动而非复制：这里的副本是 Husk 自己的，游戏可能有几个 GB。
        TranslationLayerStore.shared.add(urls, move: true)
    }

    /// 安装到 Android——若已就绪则立即，否则待其就绪后立即。
    func sendToAndroid() {
        let urls = waiting
        waiting = []
        guard !urls.isEmpty else { return }
        forAndroid += urls
        installForAndroidIfReady()
    }

    func installForAndroidIfReady() {
        guard AndroidHost.shared.isReady, AndroidHost.shared.busy == nil, !forAndroid.isEmpty else { return }
        let urls = forAndroid
        forAndroid = []
        AndroidHost.shared.install(urls)
    }

    func discard() {
        for url in waiting { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        waiting = []
    }
}

/// 分享来的 APK 去向何处。两个选项，各自说明含义，外加一条退路。
struct IncomingChooser: View {
    @ObservedObject private var incoming = IncomingFiles.shared
    @ObservedObject private var host = AndroidHost.shared
    @ObservedObject private var guest = GuestImage.shared

    private var title: String {
        guard let first = incoming.waiting.first else { return "" }
        return incoming.waiting.count == 1 ? first.lastPathComponent : "\(incoming.waiting.count) 个文件"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("添加到 Husk").font(.title2.weight(.bold))
                Text(title).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }

            choice(icon: "bolt.fill", title: "翻译层",
                   detail: "直接在你的 iPhone 上运行游戏，无需启动 Android。最适合游戏。") {
                incoming.sendToTranslationLayer()
            }
            choice(icon: "apps.iphone", title: "Android",
                   detail: androidDetail) {
                incoming.sendToAndroid()
            }

            Button("取消", role: .cancel) { incoming.discard() }
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
        }
        .padding(22)
    }

    private var androidDetail: String {
        if host.isReady { return "安装到 Android 中，任意应用均可运行。" }
        if guest.state == .ready { return "下次 Android 启动时安装进去。" }
        return "待 Android 下载并启动后安装进去。"
    }

    private func choice(icon: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(CardButtonStyle())
    }
}
