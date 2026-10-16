// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

// MARK: - 资源库条目

/// Husk 能打开的一切：翻译层运行的游戏、安装在 Android 中的应用、或 Android 本身。
///
/// 用户无需知道某个东西是怎么跑的——Husk 知道——因此启动器按"是什么"（游戏、应用）分类，
/// 而不是按"怎么跑"分类。后一种分类唯一留下的痕迹是 Android 内应用上的小徽章，因为它需要先启动 Android。
enum LibraryItem: Identifiable, Hashable {
    case game(TLApp)
    case app(AndroidHost.Package)
    case android
    case ps4(PS4Game)

    var id: String {
        switch self {
        case .game(let g): return "tl:" + g.id
        case .ps4(let g): return g.libraryID
        case .app(let p): return "android:" + p.name
        case .android: return "android-system"
        }
    }

    static func == (a: LibraryItem, b: LibraryItem) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    var title: String {
        switch self {
        case .game(let g): return g.label
        case .app(let p): return p.label
        case .android: return "Android"
        case .ps4(let g): return g.title
        }
    }

    var iconPath: String? {
        switch self {
        case .game(let g): return g.iconPath
        case .app(let p): return p.iconPath
        case .android: return nil
        case .ps4(let g): return g.iconPath
        }
    }

    /// 翻译层上的游戏（Flutter 应用除非自称游戏否则算应用），以及 Android 本身归类为游戏的内容。
    var isGame: Bool {
        switch self {
        case .game(let g): return (g.report?.nativeEngine != .flutter && g.report?.engine != "Flutter" && g.report?.webKind == nil) || g.isGameCategory
        case .app(let p): return p.category == "Game"
        case .android: return false
        case .ps4: return true
        }
    }

    var packageName: String? {
        switch self {
        case .game(let g): return g.packageName
        case .app(let p): return p.name
        case .android: return nil
        case .ps4: return nil
        }
    }

    /// 游戏画面图，用于已在 iPhone 上跑过的应用（从 GitHub 拉取；见 ShowcaseStore）。
    @MainActor var artworkPath: String? {
        if case .ps4(let g) = self { return g.artPath }   // 游戏自己的封面图（pic1）
        return ShowcaseStore.shared.pictures(for: packageName).first
    }

    var runsInAndroid: Bool {
        if case .app = self { return true }
        return false
    }

    var lastUsed: Date? {
        switch self {
        case .game(let g): return g.lastPlayed
        case .ps4(let g): return g.lastPlayed
        case .app(let p): return p.lastUsed
        case .android: return UserDefaults.standard.object(forKey: "husk.android.lastOpened") as? Date
        }
    }

    var route: LibraryRoute {
        switch self {
        case .game(let g): return .game(g.id)
        case .app(let p): return .android(p)
        case .android: return .androidSystem
        case .ps4(let g): return .ps4(g.titleID)
        }
    }

    /// "2 小时前玩过"，或从未从 Husk 打开过则不显示。
    var usedText: String? {
        guard let date = lastUsed else { return nil }
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .full
        let ago = date.timeIntervalSinceNow > -60 ? "刚刚" : rel.localizedString(for: date, relativeTo: Date())
        return (isGame ? "玩于 " : "打开于 ") + ago
    }
}

/// 资源库页面显示哪些条目。
enum LibraryFilter: String, CaseIterable, Identifiable {
    case all, games, apps
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "全部"
        case .games: return "游戏"
        case .apps: return "应用"
        }
    }
}

/// 来自两个来源的所有条目，汇总在一个列表中。
@MainActor
enum Launcher {
    static func items(store: TranslationLayerStore, host: AndroidHost) -> [LibraryItem] {
        store.apps.map(LibraryItem.game) + PS4Store.shared.games.map(LibraryItem.ps4) + host.packages.map(LibraryItem.app)
    }

    /// 最近使用的排最前；从未使用的按名称排后。
    static func byRecent(_ items: [LibraryItem]) -> [LibraryItem] {
        items.sorted { a, b in
            switch (a.lastUsed, b.lastUsed) {
            case let (x?, y?): return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }
    }

    static var jitOn: Bool { JITBootstrap.ready }
}

// MARK: - 主页

/// 磁贴式主页：上次用过的、游戏需要的两样东西（JIT 和它的文件）、Android、以及资源库其余部分。
struct HomeView: View {
    @ObservedObject private var router = Router.shared
    @ObservedObject private var store = TranslationLayerStore.shared
    @ObservedObject private var host = AndroidHost.shared
    @ObservedObject private var jit = JITCoordinator.shared
    @ObservedObject private var incoming = IncomingFiles.shared
    @Environment(\.colorScheme) private var scheme
    @AppStorage(Holiday.key) private var holiday = true

    /// 全部条目，最近使用优先。
    private var all: [LibraryItem] { Launcher.byRecent(Launcher.items(store: store, host: host)) }

    var body: some View {
        NavigationStack(path: $router.home) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        if let icon = HuskAppIcon.current.preview(dark: scheme == .dark) {
                            Image(uiImage: icon)
                                .resizable()
                                .frame(width: 34, height: 34)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        Text("Husk")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                        if holiday { ChristmasTree(size: 30).padding(.leading, 2) }
                        Spacer()
                        HeaderButton(systemImage: "plus") { router.addSomething() }
                            .accessibilityLabel("添加游戏或应用")
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 6)

                    if let busy = incoming.preparing { BusyStrip(text: busy) }
                    if let busy = store.busy { BusyStrip(text: busy) }
                    if let busy = host.busy { BusyStrip(text: busy) }

                    let items = all
                    let lead = items.first { $0.lastUsed != nil } ?? items.first
                    VStack(spacing: 12) {
                        if let lead { LeadTile(item: lead) } else { WelcomeCard() }
                        HStack(spacing: 12) {
                            JITTile()
                            DownloadsTile()
                        }
                        AndroidTile()
                    }
                    if let error = jit.error, !Launcher.jitOn {
                        Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }

                    let rest = items.filter { $0 != lead }
                    if !rest.isEmpty {
                        ShelfHeader(title: "资源库") { router.showLibrary(.all) }
                            .padding(.horizontal, 4)
                            .padding(.top, 6)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                            ForEach(rest.prefix(UIDevice.current.userInterfaceIdiom == .pad ? 16 : 8)) { item in
                                NavigationLink(value: item.route) { LibrarySquare(item: item) }
                                    .buttonStyle(CardButtonStyle())
                                    .accessibilityLabel(item.title)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .id(jit.attachGeneration)
            }
            .scrollIndicators(.hidden)
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .libraryDestinations()
        }
    }
}

/// 主页磁贴的共同基底。
private struct Tile<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// 磁贴的图标：磁贴自身配色的小圆角方块。
private struct TileGlyph: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.48, weight: .bold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

/// 上次用过的那个：它的封面、名字、以及"开始玩"。
private struct LeadTile: View {
    let item: LibraryItem
    @ObservedObject private var router = Router.shared

    var body: some View {
        VStack(spacing: 0) {
            NavigationLink(value: item.route) {
                ItemBackdrop(item: item)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack(spacing: 12) {
                NavigationLink(value: item.route) {
                    HStack(spacing: 12) {
                        ItemIcon(item: item, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(item.usedText ?? (item.isGame ? "可以开始玩了" : "可以打开了"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button(action: play) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Color.accentColor, in: Circle())
                }
                .buttonStyle(CardButtonStyle())
                .accessibilityLabel((item.isGame ? "开始玩 " : "打开 ") + item.title)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// 游戏在其页面加载后立即启动；其他东西只打开它的页面。
    private func play() {
        if case .game(let g) = item { router.autoPlay = g.id }
        router.home.append(item.route)
    }
}

/// JIT 是否已开，以及未开时怎么开。
private struct JITTile: View {
    @ObservedObject private var jit = JITCoordinator.shared

    private var isOn: Bool { Launcher.jitOn }
    private var via: String {
        let m = jit.resolvedMethod
        return m == .builtIn ? "StikJIT" : m.title
    }

    var body: some View {
        Button(action: tap) {
            Tile {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        TileGlyph(systemImage: "bolt.fill", color: isOn ? .green : .orange)
                        Spacer()
                        if jit.busy { ProgressView() }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isOn ? "JIT 已开" : "JIT 未开").font(.headline).foregroundStyle(.primary)
                        Text(isOn ? "通过 \(via)" : jit.busy ? (jit.status ?? "正在开启…") : "点按开启")
                            .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(CardButtonStyle())
        .disabled(jit.busy)
    }

    private func tap() {
        if isOn { jit.showSetup = true; return }
        if HuskBuiltInJIT.isAvailable, jit.resolvedMethod == .builtIn { jit.method = .builtIn }
        jit.enable()
    }
}

/// 下载一览：正在拉什么，或 Husk 已是最新。
private struct DownloadsTile: View {
    @ObservedObject private var downloads = Downloads.shared
    @ObservedObject private var updates = AppUpdates.shared
    @ObservedObject private var guest = GuestImage.shared
    @ObservedObject private var router = Router.shared

    private var status: String {
        let running = downloads.jobs.filter { !$0.complete && !$0.paused && !$0.failed }
        if !running.isEmpty {
            let total = running.reduce(Int64(0)) { $0 + $1.total }
            let got = running.reduce(Int64(0)) { $0 + $1.received }
            let pct = total > 0 ? " · \(Int(Double(got) / Double(total) * 100))%" : ""
            return "\(running.count) 个下载中\(pct)"
        }
        if downloads.jobs.contains(where: \.failed) { return "有任务失败" }
        if let release = updates.available { return "Husk \(release.version) 已发布" }
        if guest.update.isSomething { return "Android 更新就绪" }
        return "已是最新"
    }

    var body: some View {
        Button { router.showDownloads = true } label: {
            Tile {
                VStack(alignment: .leading, spacing: 18) {
                    TileGlyph(systemImage: "arrow.down", color: .indigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("下载").font(.headline).foregroundStyle(.primary)
                        Text(status).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(CardButtonStyle())
    }
}

/// Android 本身，给翻译层暂时跑不了的应用用。
private struct AndroidTile: View {
    @ObservedObject private var router = Router.shared

    var body: some View {
        Tile(padding: 14) {
            HStack(spacing: 12) {
                NavigationLink(value: LibraryItem.android.route) {
                    HStack(spacing: 12) {
                        TileGlyph(systemImage: "apps.iphone", color: AndroidMark.green, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Android").font(.headline).foregroundStyle(.primary)
                            Text("给翻译层暂时跑不了的应用用")
                                .font(.footnote).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button {
                    if router.androidStarted { router.openGuest() } else { router.startAndroid() }
                } label: {
                    Text(router.androidStarted ? "打开" : "启动")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                }
                .buttonStyle(CardButtonStyle())
            }
        }
    }
}

/// 主页资源库网格中的一个方块：应用自己的图标。
private struct LibrarySquare: View {
    let item: LibraryItem

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                GeometryReader { geo in ItemIcon(item: item, size: geo.size.width) }
            }
            .overlay(alignment: .topTrailing) { if item.runsInAndroid { AndroidBadge().padding(5) } }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// 第一次使用：还没添加任何东西，以及两条入门途径。
private struct WelcomeCard: View {
    @ObservedObject private var router = Router.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 60, height: 60)
                .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text("添加你的第一个游戏")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Text("选一个 APK 或整包（.xapk、.apkm、.apks），或从「文件」、Safari 分享到 Husk。游戏直接在你的 iPhone 上运行，"
                   + "其他应用在 Android 内部运行。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { router.addSomething() } label: {
                Text("添加游戏或应用").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct ShelfHeader: View {
    let title: String
    let seeAll: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(.title3, design: .rounded).weight(.bold))
            Spacer()
            Button("查看全部", action: seeAll).font(.subheadline.weight(.semibold))
        }
        .padding(.bottom, -10)
    }
}

// MARK: - 封面图

/// 顶替封面图的图片，由图标生成：图标本身放大模糊铺满区域，下方压暗渐变以保证文字可读。
/// Android 图标是大多数应用仅有的图，这就是把它们撑大的方式。
struct IconBackdrop: View {
    let path: String?
    var fallback: Color = Color(uiColor: .secondarySystemBackground)

    var body: some View {
        ZStack {
            fallback
            if path != nil {
                AppIcon(path: path, size: 120)
                    .scaleEffect(3.2)
                    .blur(radius: 28)
                    .saturation(1.3)
                    .opacity(0.9)
            }
        }
        .clipped()
        // 放大后图标远超出卡片；裁剪隐藏了它但不阻止它接收触摸，
        // 曾出现点一张封面却落在隔壁封面的问题。
        .allowsHitTesting(false)
    }
}

/// 条目名称后方的图：Husk 自带游戏画面时用它，否则用模糊图标。
struct ItemBackdrop: View {
    let item: LibraryItem
    var pixels: Int = 1200
    var fallback: Color = Color(uiColor: .secondarySystemBackground)
    @ObservedObject private var showcase = ShowcaseStore.shared

    var body: some View {
        Group {
            if let art = item.artworkPath {
                Color.clear.overlay { PictureView(path: art, pixels: pixels) }.clipped()
            } else {
                IconBackdrop(path: item.iconPath, fallback: item == .android ? AndroidMark.green.opacity(0.55) : fallback)
            }
        }
        .allowsHitTesting(false)
    }
}

/// 条目的图标：应用自己的图标，或 Android 本身用 Android 标志。
struct ItemIcon: View {
    let item: LibraryItem
    let size: CGFloat

    var body: some View {
        if item == .android {
            AndroidMark(size: size)
        } else {
            AppIcon(path: item.iconPath, size: size)
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
        }
    }
}

/// Android 本身作为图标。
struct AndroidMark: View {
    static let green = Color(red: 0.24, green: 0.86, blue: 0.52)
    var size: CGFloat = 64

    var body: some View {
        Image(systemName: "apps.iphone")
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Self.green.gradient, in: RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
    }
}

/// "在 Android 内打开"徽章。
struct AndroidBadge: View {
    var body: some View {
        Text("ANDROID")
            .font(.system(size: 8, weight: .heavy, design: .rounded))
            .tracking(0.4)
            .foregroundStyle(Color(red: 0.03, green: 0.13, blue: 0.06))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(AndroidMark.green, in: Capsule())
    }
}

// MARK: - 资源库

/// 所有游戏和应用在一个网格里：搜索，以及全部 / 游戏 / 应用。
struct LibraryScreen: View {
    @ObservedObject private var router = Router.shared
    @ObservedObject private var store = TranslationLayerStore.shared
    @ObservedObject private var host = AndroidHost.shared
    @ObservedObject private var guest = GuestImage.shared
    @State private var query = ""

    var body: some View {
        NavigationStack(path: $router.library) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("资源库")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                        Spacer()
                        HeaderButton(systemImage: "plus") { router.addSomething() }
                            .accessibilityLabel("添加游戏或应用")
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 6)
                    SearchField(text: $query, prompt: "搜索游戏和应用")
                    Picker("显示", selection: $router.libraryFilter) {
                        ForEach(LibraryFilter.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if let busy = store.busy { BusyStrip(text: busy) }
                    if let busy = host.busy { BusyStrip(text: busy) }

                    let items = Launcher.items(store: store, host: host)
                        .filter { matches(query, $0.title) }
                        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                    let games = items.filter(\.isGame)
                    // Android 作为它自己的应用：钉在最前，也像其他东西一样可被搜索到。
                    let apps = (matches(query, "Android") ? [LibraryItem.android] : []) + items.filter { !$0.isGame }

                    if router.libraryFilter != .apps {
                        section("游戏", games, empty: query.isEmpty ? "点 + 按钮添加游戏。" : nil)
                    }
                    if router.libraryFilter != .games {
                        section("应用", apps, empty: nil)
                    }
                    if !query.isEmpty, games.isEmpty, apps.isEmpty { NoResults(query: query) }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .libraryDestinations()
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [LibraryItem], empty: String?) -> some View {
        if !items.isEmpty || empty != nil {
            Tile {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(title).font(.headline)
                        Text("\(items.count)").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if items.isEmpty, let empty {
                        Text(empty).font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top),
                                                 count: UIDevice.current.userInterfaceIdiom == .pad ? 8 : 4),
                                  spacing: 18) {
                            ForEach(items) { item in
                                NavigationLink(value: item.route) {
                                    LauncherTile(title: item.title, iconPath: item.iconPath, item: item, caption: caption(item), size: 60)
                                }
                                .buttonStyle(CardButtonStyle())
                            }
                        }
                    }
                }
            }
        }
    }

    private func caption(_ item: LibraryItem) -> String? {
        switch item {
        case .game(let g):
            if g.packageName == GeodeSupport.launcherPackage { return "Geode" }
            return g.report?.canRun == true ? nil : "可能无法运行"
        case .android:
            if AndroidHost.shared.isReady { return "运行中" }
            return guest.state == .ready ? nil : "尚未安装"
        case .app: return nil
        case .ps4: return PS4Store.available ? nil : "需要 iOS 17.4"
        }
    }
}

// MARK: - 共享组件

/// 网格中的一个应用，像主屏那样绘制：图标，下方是名字。
struct LauncherTile: View {
    let title: String
    let iconPath: String?
    var item: LibraryItem? = nil
    var caption: String? = nil
    var size: CGFloat = 64
    @ObservedObject private var statuses = GameStatusStore.shared

    /// 上次玩的结果，在 Husk 见过它被玩过之后。
    private var result: GameStatusStore.Result? {
        guard case .game(let g)? = item else { return nil }
        return statuses.status(g.id)?.result
    }

    var body: some View {
        VStack(spacing: 7) {
            Group {
                Group { if let item { ItemIcon(item: item, size: size) } else { AppIcon(path: iconPath, size: size) } }.snowCap(height: 7)
            }
            .shadow(color: .black.opacity(0.14), radius: 6, y: 3)
            .overlay(alignment: .bottom) {
                if item?.runsInAndroid == true { AndroidBadge().offset(y: 6) }
            }
            .overlay(alignment: .topTrailing) {
                if let result { GameStatusBadge(result: result).offset(x: 5, y: -5) }
            }
            VStack(spacing: 1) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if let caption {
                    Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.top, item?.runsInAndroid == true ? 3 : 0)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

/// 屏幕头部的圆形图标按钮。
struct HeaderButton: View {
    let systemImage: String
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(enabled ? Color.accentColor : Color.secondary)
                .frame(width: 38, height: 38)
                .background(Color(uiColor: .tertiarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

/// 正在进行的工作，用一行字说明。
struct BusyStrip: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(text).font(.subheadline).lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// 系统样式的搜索框。
struct SearchField: View {
    @Binding var text: String
    let prompt: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField(prompt, text: $text)
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !text.isEmpty {
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if focused {
                Button("取消") { text = ""; focused = false }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: focused)
    }
}

/// 搜索无结果。
struct NoResults: View {
    let query: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 28, weight: .light)).foregroundStyle(.secondary)
            Text("无结果").font(.headline)
            Text("这里没有叫「\(query)」的东西。").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

/// 名称是否匹配搜索词。
func matches(_ query: String, _ names: String...) -> Bool {
    let q = query.trimmingCharacters(in: .whitespaces)
    return q.isEmpty || names.contains { $0.localizedCaseInsensitiveContains(q) }
}

extension View {
    /// 条目打开的页面，用于显示它的那个导航栈。
    func libraryDestinations() -> some View {
        navigationDestination(for: LibraryRoute.self) { route in
            LibraryRouteView(route: route).toolbar(.visible, for: .navigationBar)
        }
    }
}

private struct LibraryRouteView: View {
    let route: LibraryRoute
    @ObservedObject private var store = TranslationLayerStore.shared

    var body: some View {
        switch route {
        case .game(let id):
            if let app = store.apps.first(where: { $0.id == id }) { GamePage(app: app) } else { GoneView() }
        case .gameSettings(let id):
            if let app = store.apps.first(where: { $0.id == id }) { TLAppSettingsView(app: app) } else { GoneView() }
        case .gameReport(let id):
            if let app = store.apps.first(where: { $0.id == id }) { TLTechnicalView(app: app) } else { GoneView() }
        case .android(let pkg):
            AndroidAppPage(app: pkg)
        case .androidSystem:
            AndroidSystemPage()
        case .ps4(let id):
            if let game = PS4Store.shared.game(id) { PS4GamePage(game: game) } else { GoneView() }
        }
    }
}

private struct GoneView: View {
    var body: some View {
        Text("此项已被移除。").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
