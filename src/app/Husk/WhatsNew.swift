// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

// MARK: - 新特性

/// 本版本带来的新功能，在更新到该版本后展示一次（首次安装不展示：那时由引导页欢迎用户）。
enum WhatsNew {
    struct Item: Identifiable {
        let symbol: String
        let title: String
        let detail: String
        var id: String { title }
    }

    /// 这些说明对应的版本号。同一版本的重复构建不会再次展示。
    static let version = "1.0.1"
    static let items: [Item] = [
        Item(symbol: "bag.fill", title: "Google Play",
             detail: "从“商店”标签页获取游戏。Play 商店下载（含拆分 APK 和资源包）均可在翻译层运行。"),
        Item(symbol: "checkmark.seal.fill", title: "Google Play 服务",
             detail: "游戏会检测到 Play 服务已安装但未登录，不再反复弹窗要求登录，继续运行。"),
        Item(symbol: "arrow.up.doc.fill", title: "存档备份",
             detail: "在游戏页面把存档备份为 .zip，之后随时恢复，或迁移到其他设备。"),
        Item(symbol: "exclamationmark.bubble.fill", title: "崩溃报告",
             detail: "游戏导致 Husk 崩溃时，下次启动会说明发生了什么，并提供可分享的报告。"),
        Item(symbol: "checkmark.circle.fill", title: "一目了然兼容性",
             detail: "资源库会标记每个游戏上次运行的结果：可玩、崩溃或无法启动。"),
        Item(symbol: "gamecontroller.fill", title: "Godot 游戏",
             detail: "使用 Godot 3 和 4 制作的游戏现已可在翻译层运行。"),
        Item(symbol: "slider.horizontal.below.square.and.square.filled", title: "自定义手柄",
             detail: "可为每个游戏移动、缩放、隐藏屏幕手柄按钮。"),
        Item(symbol: "keyboard.fill", title: "Minecraft 中打字",
             detail: "聊天、告示牌和世界名称输入框会弹出键盘。"),
        Item(symbol: "arrow.left.arrow.right", title: "切换游戏",
             detail: "关闭 Husk 去玩另一个游戏，下次打开 Husk 时它会自动启动。"),
        Item(symbol: "puzzlepiece.extension.fill", title: "Geode",
             detail: "Geometry Dash 的 Mod（含 Geode 5），可在游戏设置中开启。"),
    ]

    private static let seenKey = "husk.whatsNew.seen"

    /// 当前是否应展示更新说明：是更新到本版本，而非全新安装。
    static var due: Bool {
        let seen = UserDefaults.standard.string(forKey: seenKey)
        if seen == version { return false }
        if Onboarding.needed { markSeen(); return false }       // 首次安装：由引导页欢迎用户
        return true
    }

    static func markSeen() { UserDefaults.standard.set(version, forKey: seenKey) }
}

struct WhatsNewSheet: View {
    var done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Husk \(WhatsNew.version) 新特性").font(.largeTitle.weight(.bold))
                        Text("首个正式完整版。").foregroundStyle(.secondary)
                    }
                    .padding(.top, 36)
                    ForEach(WhatsNew.items) { item in
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 26))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 36)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title).font(.headline)
                                Text(item.detail).font(.subheadline).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
            }
            Button(action: done) {
                Text("继续").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
        .interactiveDismissDisabled()
    }
}

// MARK: - 检查更新

/// GitHub 上的新版 Husk：启动时询问 releases 页面（每天最多两次），每个版本只通知一次。
@MainActor
final class AppUpdates: ObservableObject {
    static let shared = AppUpdates()

    struct Release: Equatable {
        let version: String
        let page: URL
    }

    @Published var available: Release?

    private static let api = URL(string: "https://api.github.com/repos/Leviidev/Husk/releases/latest")!
    private static let checkedKey = "husk.updates.checked", dismissedKey = "husk.updates.dismissed"

    static var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    func check() async {
        let d = UserDefaults.standard
        if Date().timeIntervalSince1970 - d.double(forKey: Self.checkedKey) < 12 * 3600 { return }
        var req = URLRequest(url: Self.api)
        req.timeoutInterval = 20
        req.setValue("Husk", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String,
              let page = (obj["html_url"] as? String).flatMap(URL.init(string:)) else { return }
        d.set(Date().timeIntervalSince1970, forKey: Self.checkedKey)
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard Self.newer(version, than: Self.current), d.string(forKey: Self.dismissedKey) != version else { return }
        HuskLog.log("update", "Husk \(version) is out (this is \(Self.current))")
        available = Release(version: version, page: page)
    }

    func dismiss() {
        if let v = available?.version { UserDefaults.standard.set(v, forKey: Self.dismissedKey) }
        available = nil
    }

    /// "1.0.10" 比 "1.0.9" 新：逐段比较数字。
    static func newer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
}
