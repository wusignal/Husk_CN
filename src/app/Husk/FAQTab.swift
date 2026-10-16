// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// FAQ 标签页：常见问题与解决办法，让卡在 JIT 或某个打不开的应用上的用户
/// 不必离开 Husk 就能找到答案。
struct FAQTab: View {
    @State private var query = ""

    private var sections: [FAQ.Section] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return FAQ.sections }
        return FAQ.sections.compactMap { s in
            let items = s.items.filter { $0.question.localizedCaseInsensitiveContains(q) || $0.answer.localizedCaseInsensitiveContains(q) }
            return items.isEmpty ? nil : FAQ.Section(title: s.title, symbol: s.symbol, items: items)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections) { s in
                    Section {
                        ForEach(s.items) { item in FAQRow(item: item, expanded: !query.isEmpty) }
                    } header: {
                        Label(s.title, systemImage: s.symbol)
                    }
                }
                if sections.isEmpty {
                    Text("没有与“\(query)”相关的结果。打开“设置 › 关于 › 打开控制台”可查看 Husk 正在做什么。")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("常见问题")
            .searchable(text: $query, prompt: "搜索问题")
        }
    }
}

private struct FAQRow: View {
    let item: FAQ.Item
    var expanded: Bool
    @State private var open = false

    var body: some View {
        DisclosureGroup(isExpanded: Binding(get: { open || expanded }, set: { open = $0 })) {
            Text(.init(item.answer))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
        } label: {
            Text(item.question).font(.body.weight(.medium))
        }
    }
}

enum FAQ {
    struct Item: Identifiable { let question: String; let answer: String; var id: String { question } }
    struct Section: Identifiable { let title: String; let symbol: String; let items: [Item]; var id: String { title } }

    static let sections: [Section] = [
        Section(title: "JIT", symbol: "bolt.fill", items: [
            Item(question: "什么是 JIT？Husk 为什么需要它？",
                 answer: "Android 应用和游戏在运行时编译代码，这需要一块“可写可执行”的内存。"
                       + "iOS 只在有调试器附着到 App 时才允许这种内存。开启 JIT 就是短暂附着一个调试器。"
                       + "没有它，Husk 可以显示资源库，但无法启动 Android 或游戏。"),
            Item(question: "我该用哪种方式开启 JIT？",
                 answer: "• **iOS 27 及以上：**设置 › JIT › 在本机配对。无需电脑。\n"
                       + "• **iOS 26：**StikJIT（内置），需在电脑上生成配对文件，并配合 LocalDevVPN。\n"
                       + "• **更老的 iOS，或 Husk 运行在 LiveContainer 内：**使用 StikDebug App。\n"
                       + "• **用 TrollStore 安装：**TrollStore，并开启其 URL Scheme 设置。\n"
                       + "• **用 Dopamine 越狱：**在越狱设置中开启“允许 App 使用 JIT”。"),
            Item(question: "StikJIT 提示无法连接，或“启用 JIT”失败",
                 answer: "1. 确认已安装并连接 **LocalDevVPN**，状态栏应出现 VPN 图标。\n"
                       + "2. 必须开启 Wi-Fi，尽管数据并不离开你的 iPhone。\n"
                       + "3. 必须开启 **开发者模式**（设置 › 隐私与安全性 › 开发者模式）。\n"
                       + "4. 首次使用时 Husk 会下载 Apple 的开发者磁盘镜像，可能需要一分钟，请耐心等待。\n"
                       + "5. 仍失败？关闭再打开 LocalDevVPN，然后重新配对。"),
            Item(question: "开发者模式里没有“与 Husk 配对”",
                 answer: "先在 Husk 里点 **开始配对**，并在弹窗中允许 **本地网络** 权限。如果之前拒绝过，"
                       + "请到 设置 › 隐私与安全性 › 本地网络 › Husk 中打开。必须开启 Wi-Fi。"
                       + "开发者模式必须已启用，首次开启会重启 iPhone。"),
            Item(question: "我的配对文件突然失效了",
                 answer: "当 iPhone 的信任设置被重置，或某次 iOS 更新后，配对文件会失效。"
                       + "重新生成一个；若你在 iOS 27 上，可直接在 iPhone 上配对，然后到 设置 › JIT 中重新导入。"),
            Item(question: "StikDebug 能打开，但 JIT 还是没开",
                 answer: "单独打开 StikDebug，确认它里有你的配对文件，且 LocalDevVPN 已连接。"
                       + "把 StikDebug 更新到最新版。Husk 会自己把脚本发给 StikDebug，不需要在 StikDebug 里为 Husk 做任何设置。"),
            Item(question: "为什么每次都要重新开启 JIT？",
                 answer: "JIT 只在 Husk 运行期间有效。当 iOS 在后台关闭 Husk，或你手动上滑关闭后，下次启动需要重新开启。"
                       + "使用“本机配对”或配对文件时，只需点一下即可。"),
            Item(question: "没有 JIT 能使用 Husk 吗？",
                 answer: "可以浏览和导入应用，但任何 Android 内容都无法运行。每个游戏和应用都需要 JIT。"),
        ]),
        Section(title: "Husk 本身", symbol: "app.badge", items: [
            Item(question: "Husk 完全打不开",
                 answer: "• **打开后立刻闪退：**签名证书很可能已过期。免费 Apple 账号证书有效期 7 天。"
                       + "用你的侧载工具重新签名或重装 Husk，应用和存档都在。\n"
                       + "• **提示“未受信任的开发者”：**前往 设置 › 通用 › VPN 与设备管理，信任你的证书。\n"
                       + "• **要求开启开发者模式：**在 设置 › 隐私与安全性 中开启。"),
            Item(question: "我玩游戏时 Husk 闪退了",
                 answer: "再次打开 Husk 时它会说明发生了什么，并提供可分享的报告。通常是游戏内存耗尽，"
                       + "或遇到了 Husk 暂不支持的特性。关掉其他 App；若反复出现，请分享报告。"),
            Item(question: "如何获取日志以反馈问题？",
                 answer: "在资源库中打开该应用的页面，点 **分享报告**。Husk 自身日志则前往"
                       + "设置 › 关于 › **打开控制台**。在那里开启 **开发者信息** 可获得更详细内容。"),
            Item(question: "如何更新 Husk？",
                 answer: "有新版本时 Husk 会提示你。用同一个侧载工具把新 IPA 覆盖安装到旧版上即可。"
                       + "你的资源库、应用和存档都会保留。"),
        ]),
        Section(title: "应用与游戏", symbol: "gamecontroller.fill", items: [
            Item(question: "应用打不开",
                 answer: "在资源库中打开它的页面，Husk 会说明原因：\n"
                       + "• **受保护的应用：**它会检测是否运行在真实 Android 手机上，或使用了反作弊/DRM。Husk 无法绕过这些。\n"
                       + "• **CPU 架构不对：**APK 只有 32 位代码。请找 arm64（arm64-v8a）版本。\n"
                       + "• **应用不完整或缺少游戏数据：**APK 需要拆分文件或 OBB。请导入完整的 .apks、.xapk 或 .apkm。\n"
                       + "• **依赖 Google 服务：**应用需要 Google 账号或 Play 服务，而 Husk 无法提供。\n"
                       + "• **用到了 Husk 暂不支持的特性：**请分享报告，以便后续适配。"),
            Item(question: "屏幕一直黑屏",
                 answer: "大型游戏首次启动需要准备代码和数据，最长可能一分钟。"
                       + "若之后仍黑屏，关闭后再试一次；若无变化，请分享报告。"),
            Item(question: "修改版或重打包的 APK 崩溃",
                 answer: "APKVISION 等站点的重打包版本常把应用代码改成自己的库，或加入篡改检测，"
                       + "因此更容易出问题。请尝试开发者原版 APK 或 APKMirror 上的版本。"),
            Item(question: "可以导入哪些文件？",
                 answer: ".apk，以及拆分包 .apks、.xapk 或 .apkm。可以分享到 Husk、从“文件”中打开，或在资源库点 + 号。"),
            Item(question: "游戏卡顿或手机发烫",
                 answer: "关掉其他 App，让手机冷却。游戏是原生运行的，但部分在真实 Android 手机上由硬件完成的工作在这里由 CPU 承担。"
                       + "低电量模式也会拖慢 Husk。"),
            Item(question: "可以连接手柄吗？",
                 answer: "可以。在 iPhone 的蓝牙设置中配对手柄，支持手柄的游戏会自动识别。"),
            Item(question: "游戏运行时可以使用 Husk 的其他功能吗？",
                 answer: "在设置中开启 **在窗口中打开应用**。应用会在可移动、可缩放、可最小化的窗口中打开。"),
            Item(question: "Google 登录用不了",
                 answer: "Husk 没有 Google Play 服务，因此“使用 Google 登录”按钮可能失败。若应用提供邮箱或其他登录方式，请改用它们。"),
        ]),
        Section(title: "存档与存储", symbol: "externaldrive.fill", items: [
            Item(question: "我的存档在哪里？",
                 answer: "每个应用的数据都保存在 Husk 内部。在应用页面，**备份存档** 会导出数据，**恢复存档** 会导回，"
                       + "也可以迁移到另一台 iPhone。"),
            Item(question: "Husk 占用空间很大",
                 answer: "导入的应用及其数据保存在 Husk 的文件夹中。在游戏页面删除你不再玩的游戏即可。"
                       + "完整 Android 系统镜像约多占 2 GB，仅在使用 Android 本身时才需要。"),
        ]),
        Section(title: "Android 系统", symbol: "cpu", items: [
            Item(question: "翻译层应用和完整 Android 系统有什么区别？",
                 answer: "大多数应用和游戏直接在你的 iPhone 上原生运行。完整 Android 系统是另一个更慢的选项，"
                       + "用于那些只能在真实 Android 里运行的内容。"),
            Item(question: "Android 启动很慢",
                 answer: "首次启动会下载 Android 镜像并冷启动，需要几分钟。"
                       + "之后 Husk 会恢复已保存的虚拟机状态，快很多。"),
        ]),
    ]
}
