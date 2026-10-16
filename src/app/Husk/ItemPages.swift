// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

// MARK: - 页面顶部

/// 每个条目的页面都以其封面图开场：图标压在自身模糊压暗的副本上，下方是名称、一行副标题，
/// 以及唯一要做的事——玩、打开、启动——作为一个大按钮。
private struct PageHero<Action: View>: View {
    let item: LibraryItem
    let subtitle: String
    @ViewBuilder var action: Action

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                ItemBackdrop(item: item, fallback: Color(uiColor: .tertiarySystemFill))
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                HStack(alignment: .bottom, spacing: 14) {
                    ItemIcon(item: item, size: 84)
                        .shadow(color: .black.opacity(0.35), radius: 12, y: 5)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.system(.title2, design: .rounded).weight(.heavy))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(2)
                    }
                    .foregroundStyle(.white)
                    Spacer(minLength: 0)
                }
                .padding(16)
            }
            .frame(height: 210)
            action
                .padding(14)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// 页面的主按钮。
private struct BigButton: View {
    let title: String
    let systemImage: String
    var prominent = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(.headline, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .foregroundStyle(prominent ? Color.white : Color.accentColor)
                .background(prominent ? Color.accentColor : Color.accentColor.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(CardButtonStyle())
    }
}

/// 作为 List 第一行、贴边铺满的封面。
private extension View {
    func heroRow() -> some View {
        listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
    }
}

private func fileBytes(_ paths: [String]) -> String {
    let total = paths.reduce(Int64(0)) { sum, p in
        sum + (((try? FileManager.default.attributesOfItem(atPath: p)[.size]) as? NSNumber)?.int64Value ?? 0)
    }
    return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
}

@MainActor private func turnOnJIT() {
    let jit = JITCoordinator.shared
    if HuskBuiltInJIT.isAvailable { jit.method = .builtIn }
    jit.enable()
}

// MARK: - 游戏

/// 翻译层游戏：开始玩、它的设置、它是什么、以及移除它。
struct GamePage: View {
    let app: TLApp
    @ObservedObject private var showcase = ShowcaseStore.shared

    @ObservedObject private var store = TranslationLayerStore.shared
    @ObservedObject private var jit = JITCoordinator.shared
    @Environment(\.dismiss) private var dismiss
    @State private var playing = false
    @State private var confirmRemove = false
    @State private var backupFile: URL?
    @State private var savesBusy = false
    @State private var savesMessage: String?
    @State private var confirmRestore: URL?
    @State private var confirmQuit = false
    @State private var reporting: CompatSubject?

    private var runs: Bool { app.report?.canRun == true }

    private var compatSubject: CompatSubject? {
        app.packageName.map { CompatSubject(package: $0, name: app.label, isGame: LibraryItem.game(app).isGame, iconPath: app.iconPath) }
    }

    /// 本次 Husk 运行中已加载了另一个游戏：引擎无法卸载，因此在关闭并重开 Husk 之前这个游戏无法启动。
    private var blockedBy: String? {
        guard let loaded = husk_native_loaded_apk().map({ String(cString: $0) }), let apk = app.apks.first, loaded != apk
        else { return nil }
        return store.apps.first { $0.apks.first == loaded }?.label ?? "另一个游戏"
    }

    private var preflight: AppDiagnosis? { AppDiagnosis.preflight(app) }

    private var subtitle: String {
        if let used = LibraryItem.game(app).usedText { return used }
        return runs ? "可以游玩" : "可能无法在这台 iPhone 上运行"
    }

    var body: some View {
        List {
            Section {
                PageHero(item: .game(app), subtitle: subtitle) { primary }
            } footer: {
                if isGeodeLauncher {
                    Text("这是 Geode 的 Android 启动器。在 Husk 上，Geode 实际运行在 Geometry Dash 内部：在此处开启"
                       + "（或在 Geometry Dash 的设置 › Mods 中开启），然后启动 Geometry Dash，用主菜单上的 Geode 按钮获取 Mod。"
                       + "此 APK 提供 Geode 需要的一个库，请保留它。")
                } else if let other = blockedBy {
                    Text("\(other) 仍在运行中，而游戏一旦启动就无法卸载引擎。请用上方按钮关闭 Husk，"
                       + "然后重新打开即可游玩 \(app.label)。")
                } else if !runs {
                    Text("此 APK 不含 Husk 可运行的 64 位代码，很可能无法启动。")
                }
            }
            .heroRow()

            // 启动前文件已说明的问题：损坏的 APK、错误的 CPU、缺失的分片、拒绝 Husk 的保护
            if let d = preflight {
                Section {
                    AppDiagnosisCard(diagnosis: d)
                        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                }
            }
            // 上次停止的原因，直到它再次成功运行
            if let d = GameStatusStore.shared.diagnosis(app.id), d != preflight {
                Section("上次运行") {
                    AppDiagnosisCard(diagnosis: d, showsEvidence: true)
                        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                }
            }

            if let compatSubject, !isGeodeLauncher {
                CompatibilitySection(subject: compatSubject, reporting: $reporting)
            }

            if !ShowcaseStore.shared.pictures(for: app.packageName).isEmpty {
                Section("截图") {
                    ShowcaseGallery(package: app.packageName)
                        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                }
            }

            Section {
                NavigationLink(value: LibraryRoute.gameSettings(app.id)) {
                    Label("游戏设置", systemImage: "slider.horizontal.3")
                }
                NavigationLink(value: LibraryRoute.gameReport(app.id)) {
                    Label("技术详情", systemImage: "cpu")
                }
            }

            if !isGeodeLauncher {
                Section {
                    Button { backUp() } label: { Label("备份存档", systemImage: "square.and.arrow.up") }
                        .disabled(savesBusy || !SaveBackup.hasData(app))
                    Button { pickRestore() } label: { Label("恢复存档", systemImage: "clock.arrow.circlepath") }
                        .disabled(savesBusy || loadedNow)
                } header: {
                    Text("存档")
                } footer: {
                    if let savesMessage { Text(savesMessage) }
                    else if loadedNow { Text("\(app.label) 已在本次 Husk 运行中启动。请关闭 Husk 再重开以恢复存档。") }
                    else { Text("备份是 \(app.label) 在 Husk 中保存内容的 .zip，可保存在“文件”中或迁移到其他设备。") }
                }
            }

            Section("关于") {
                LabeledContent("运行方式", value: app.report?.runnerName ?? "未知")
                if let st = GameStatusStore.shared.status(app.id) {
                    LabeledContent("上次结果") {
                        Label(st.result.label, systemImage: st.result.symbol).foregroundStyle(st.result.color)
                    }
                }
                LabeledContent("上次游玩", value: app.lastPlayed.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "从未")
                LabeledContent("大小", value: fileBytes(app.apks))
            }

            Section {
                Button(role: .destructive) { confirmRemove = true } label: {
                    Label("移除游戏", systemImage: "trash")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(app.label)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $playing, onDismiss: askHowItRan) { TLAttemptView(app: app) }
        .sheet(item: $reporting) { CompatReportSheet(subject: $0) }
        .sheet(item: Binding(get: { backupFile.map(IdentifiedURL.init) }, set: { backupFile = $0?.url })) { f in
            ShareSheet(items: [f.url])
        }
        .confirmationDialog("替换 \(app.label) 的存档？", isPresented: Binding(get: { confirmRestore != nil }, set: { if !$0 { confirmRestore = nil } }),
                            titleVisibility: .visible) {
            Button("替换", role: .destructive) { if let url = confirmRestore { restore(url) } }
        } message: {
            Text("\(app.label) 当前保存的内容将被备份替换。想保留现有存档请先备份。")
        }
        .confirmationDialog("关闭 Husk？", isPresented: $confirmQuit, titleVisibility: .visible) {
            Button("关闭 Husk") {
                // 已加载的游戏随 Husk 一起关闭，这是它正常的退出方式，并非崩溃；
                // 而这个游戏会在 Husk 再次打开时自行启动。
                Router.shared.switchTo(app.id)
                CrashReport.gameEnded()
                HuskLog.flushNow()
                exit(0)
            }
        } message: {
            Text("\(blockedBy ?? "另一个游戏") 仍在运行，而每次会话只能运行一个游戏。Husk 将关闭；重新打开后 \(app.label) 会自行启动。")
        }
        .confirmationDialog("移除 \(app.label)？", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("移除", role: .destructive) {
                dismiss()
                store.remove(app)
            }
        } message: {
            Text("此游戏及其在 Husk 中保存的所有内容将被删除。")
        }
        .id(jit.attachGeneration)
        .onAppear {
            // 等到 JIT 开启：此页在调试器附着时重建（上方 .id），然后开始游玩。
            guard Router.shared.autoPlay == app.id, Launcher.jitOn, blockedBy == nil else { return }
            Router.shared.autoPlay = nil
            play()
        }
    }

    /// 开始游玩：若开启了 Geode，先把它缺的东西（新版本、资源）拉下来。
    private func play() {
        guard TLAppSettings.load(app.id).geode, case .ready = GeodeSupport.shared.current(app) else {
            if TLAppSettings.load(app.id).geode {
                Task { await GeodeSupport.shared.prepare(app); start() }
            } else {
                start()
            }
            return
        }
        start()
    }

    /// 一次成功运行之后：跑得怎么样？每个游戏每个构建一次，且仅在确实玩过时询问（崩溃有自己的弹窗）。
    private func askHowItRan() {
        guard var subject = compatSubject, CompatibilityStore.shared.shouldAsk(subject.package),
              GameStatusStore.shared.status(app.id)?.result == .plays else { return }
        subject.afterPlaying = true
        Task { try? await Task.sleep(nanoseconds: 500_000_000); reporting = subject }
    }

    /// 全屏；或当此应用在多任务设置中允许时，在 Husk 之上以窗口打开。
    private func start() {
        if app.report?.runsOnNativeRuntime == true || app.report?.webKind != nil, AppWindows.opensInWindow(app) {
            AppWindows.shared.open(app)
        } else {
            AppWindows.shared.close(app)
            playing = true
        }
    }

    /// 本游戏的引擎已在本次 Husk 运行中加载，其文件可能正被打开：不能在它下面恢复存档。
    private var loadedNow: Bool {
        guard let loaded = husk_native_loaded_apk().map({ String(cString: $0) }) else { return false }
        return loaded == app.apks.first
    }

    private func backUp() {
        savesBusy = true; savesMessage = nil
        let app = self.app
        Task.detached {
            let result = Result { try SaveBackup.export(app) }
            await MainActor.run {
                savesBusy = false
                switch result {
                case .success(let url): backupFile = url
                case .failure(let e): savesMessage = e.localizedDescription
                }
            }
        }
    }

    private func pickRestore() {
        HuskFilePicker.present(types: [.zip], multiple: false) { urls in
            if let url = urls.first { confirmRestore = url }
        } onFail: { savesMessage = $0 }
    }

    private func restore(_ url: URL) {
        savesBusy = true; savesMessage = nil
        let app = self.app
        Task.detached {
            let result = Result { try SaveBackup.restore(app, from: url) }
            await MainActor.run {
                savesBusy = false
                switch result {
                case .success(let n): savesMessage = "已从 \(url.lastPathComponent) 恢复 \(n) 个文件。"
                case .failure(let e): savesMessage = e.localizedDescription
                }
            }
        }
    }

    /// Geode 的 Android 启动器，被当作游戏添加：它是一个完整 Android 应用，Husk 不运行。
    /// 在 Husk 上 Geode 从 Geometry Dash 自己的设置中开启，此 APK 只是给它借一个库。
    private var isGeodeLauncher: Bool { app.packageName == GeodeSupport.launcherPackage }
    private var geometryDash: TLApp? { store.apps.first { $0.packageName == GeodeSupport.gamePackage } }

    @ViewBuilder
    private var primary: some View {
        if isGeodeLauncher {
            if let gd = geometryDash {
                BigButton(title: TLAppSettings.load(gd.id).geode ? "Geode 已为 Geometry Dash 开启" : "为 Geometry Dash 开启 Geode",
                          systemImage: "puzzlepiece.extension.fill", prominent: !TLAppSettings.load(gd.id).geode) {
                    var s = TLAppSettings.load(gd.id)
                    s.geode = true
                    s.save(gd.id)
                    Task { await GeodeSupport.shared.prepare(gd) }
                }
            } else {
                BigButton(title: "请先添加 Geometry Dash", systemImage: "plus", prominent: false) { }.disabled(true)
            }
        } else if blockedBy != nil {
            BigButton(title: "关闭 Husk 以开始游玩", systemImage: "xmark.circle", prominent: false) { confirmQuit = true }
        } else if !Launcher.jitOn {
            if jit.busy {
                HStack(spacing: 10) { ProgressView(); Text(jit.status ?? "正在开启 JIT…").foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity).frame(height: 50)
            } else {
                BigButton(title: "开启 JIT 以游玩", systemImage: "bolt.fill", action: turnOnJIT)
            }
        } else {
            BigButton(title: runs ? "开始玩" : "尝试运行", systemImage: "play.fill", prominent: runs) { play() }
        }
    }
}

// MARK: - PS4 游戏

/// 来自 Documents/PS4 Games 的 PS4 游戏：开始玩，以及它是什么。由 PS4 层（libhuskps4.dylib）在 Husk 的 JIT 上运行。
struct PS4GamePage: View {
    let game: PS4Game
    @ObservedObject private var jit = JITCoordinator.shared
    @State private var playing = false
    @State private var confirmQuit = false

    private var item: LibraryItem { .ps4(game) }

    /// 本次 Husk 运行中已加载的另一个游戏（Android 游戏的引擎，或另一个 PS4 游戏）。
    private var blockedBy: String? {
        if Router.shared.androidStarted { return "Android" }   // QEMU 占着 PS4 层需要的 JIT 区域
        guard let loaded = husk_native_loaded_apk().map({ String(cString: $0) }), loaded != game.libraryID else { return nil }
        if loaded.hasPrefix("ps4:") { return PS4Store.shared.game(String(loaded.dropFirst(4)))?.title ?? "另一个游戏" }
        return TranslationLayerStore.shared.apps.first { $0.apks.first == loaded }?.label ?? "另一个游戏"
    }

    private var subtitle: String {
        if let used = item.usedText { return used }
        return "PlayStation 4" + (game.version.map { " · v\($0)" } ?? "")
    }

    var body: some View {
        List {
            PageHero(item: item, subtitle: subtitle) { primary }
                .heroRow()
            if !PS4Store.available {
                Section {
                    Text(PS4Store.moduleURL == nil
                         ? "此 Husk 构建未包含 PS4 层。"
                         : "PS4 游戏需要 iOS 17.4 或更高版本。")
                        .foregroundStyle(.secondary)
                }
            }
            Section("关于") {
                LabeledContent("运行方式", value: "Husk 的 PS4 层")
                LabeledContent("标题 ID", value: game.titleID)
                if let v = game.version { LabeledContent("版本", value: v) }
                LabeledContent("上次游玩", value: game.lastPlayed.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "从未")
                LabeledContent("文件夹", value: "PS4 Games/" + game.folder.lastPathComponent)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(game.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $playing) { PS4PlayView(game: game) }
        .confirmationDialog("关闭 Husk？", isPresented: $confirmQuit, titleVisibility: .visible) {
            Button("关闭 Husk") {
                Router.shared.switchTo(game.libraryID)
                CrashReport.gameEnded()
                HuskLog.flushNow()
                exit(0)
            }
        } message: {
            Text("\(blockedBy ?? "另一个游戏") 仍在运行，而每次会话只能运行一个游戏。Husk 将关闭；重新打开后 \(game.title) 会自行启动。")
        }
        .id(jit.attachGeneration)
        .onAppear {
            guard Router.shared.autoPlay == game.libraryID, Launcher.jitOn, blockedBy == nil, PS4Store.available else { return }
            Router.shared.autoPlay = nil
            playing = true
        }
    }

    @ViewBuilder
    private var primary: some View {
        if !PS4Store.available {
            BigButton(title: "无法在此运行", systemImage: "xmark.octagon", prominent: false) { }.disabled(true)
        } else if blockedBy != nil {
            BigButton(title: "关闭 Husk 以开始游玩", systemImage: "xmark.circle", prominent: false) { confirmQuit = true }
        } else if !Launcher.jitOn {
            if jit.busy {
                HStack(spacing: 10) { ProgressView(); Text(jit.status ?? "正在开启 JIT…").foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity).frame(height: 50)
            } else {
                BigButton(title: "开启 JIT 以游玩", systemImage: "bolt.fill", action: turnOnJIT)
            }
        } else {
            BigButton(title: "开始玩", systemImage: "play.fill") { playing = true }
        }
    }
}

// MARK: - Android 内的应用

/// 安装在 Android 中的应用：打开（未运行时先启动 Android）、它是什么、以及它的文件。
struct AndroidAppPage: View {
    let app: AndroidHost.Package
    @ObservedObject private var showcase = ShowcaseStore.shared

    @ObservedObject private var host = AndroidHost.shared
    @ObservedObject private var guest = GuestImage.shared
    @ObservedObject private var runner = QemuRunner.shared
    @ObservedObject private var router = Router.shared
    @Environment(\.dismiss) private var dismiss
    @State private var confirmUninstall = false

    private var live: AndroidHost.Package { host.packages.first { $0.name == app.name } ?? app }
    private var canOpen: Bool { host.isReady && host.busy == nil }
    private var item: LibraryItem { .app(live) }

    var body: some View {
        List {
            Section {
                PageHero(item: item, subtitle: item.usedText ?? "在 Android 内部运行") { primary }
            } footer: {
                if router.pendingAndroidLaunch == app.name, !host.isReady {
                    Text("Android 启动后会自动打开 \(live.label)。")
                }
            }
            .heroRow()

            if !ShowcaseStore.shared.pictures(for: app.name).isEmpty {
                Section("截图") {
                    ShowcaseGallery(package: app.name)
                        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                }
            }

            Section("关于") {
                LabeledContent("版本", value: live.version ?? "—")
                LabeledContent("大小", value: live.sizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—")
                LabeledContent("包名", value: live.name)
                if let b = live.bitness { LabeledContent("架构", value: b) }
            }

            Section {
                Button { router.openFiles(at: "/sdcard/Android/data/\(app.name)") } label: {
                    Label("在文件中打开", systemImage: "folder")
                }
                .disabled(!canOpen)
                Button { appInfo() } label: {
                    Label("Android 应用信息", systemImage: "info.circle")
                }
                .disabled(!canOpen)
                Button { UIPasteboard.general.string = app.name } label: {
                    Label("复制包名", systemImage: "doc.on.doc")
                }
            }

            Section {
                Button(role: .destructive) { confirmUninstall = true } label: {
                    Label("卸载", systemImage: "trash")
                }
                .disabled(!canOpen)
            } footer: {
                if !canOpen { Text("请先启动 Android，才能卸载或查看应用内部。") }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(live.label)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("卸载 \(live.label)？", isPresented: $confirmUninstall, titleVisibility: .visible) {
            Button("卸载", role: .destructive) {
                host.uninstall(app.name)
                dismiss()
            }
        } message: {
            Text("其数据将一并删除。")
        }
    }

    @ViewBuilder
    private var primary: some View {
        if canOpen {
            BigButton(title: "打开", systemImage: "play.fill") {
                host.launch(app.name) { router.openGuest() }
            }
        } else if router.androidStarted {
            VStack(spacing: 10) {
                BigButton(title: "正在启动 Android…", systemImage: "hourglass", prominent: false) { }
                    .disabled(true)
                if runner.bootProgress > 0 { ProgressView(value: Double(runner.bootProgress), total: 100) }
            }
        } else if guest.state == .ready {
            BigButton(title: Launcher.jitOn ? "启动 Android 并打开" : "开启 JIT", systemImage: Launcher.jitOn ? "play.fill" : "bolt.fill") {
                if Launcher.jitOn { router.pendingAndroidLaunch = app.name }
                router.startAndroid()
            }
        } else {
            NavigationLink(value: LibraryRoute.androidSystem) {
                Label("先获取 Android", systemImage: "arrow.down.circle")
                    .font(.system(.headline, design: .rounded))
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .foregroundStyle(.white)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(CardButtonStyle())
        }
    }

    /// Android 自己的应用页面：权限、存储、强制停止。
    private func appInfo() {
        let pkg = app.name
        DispatchQueue.global(qos: .userInitiated).async {
            _ = try? GuestBridge.shared.shell("am start -a android.settings.APPLICATION_DETAILS_SETTINGS -d package:\(pkg)", timeout: 30)
        }
        router.openGuest()
    }
}

// MARK: - Android 系统本身

/// 整个 Android 系统，作为它自己的一个 App：下载它、启动它、打开它、以及它的设置。
struct AndroidSystemPage: View {
    @ObservedObject private var guest = GuestImage.shared
    @ObservedObject private var runner = QemuRunner.shared
    @ObservedObject private var host = AndroidHost.shared
    @ObservedObject private var router = Router.shared
    @ObservedObject private var jit = JITCoordinator.shared

    private var running: Bool { router.androidStarted }

    var body: some View {
        List {
            Section {
                PageHero(item: .android, subtitle: status) {
                    VStack(spacing: 10) {
                        primary
                        if let progress { ProgressView(value: progress) }
                    }
                }
            } footer: {
                if let note { Text(note) }
            }
            .heroRow()

            if host.isReady {
                Section {
                    Button { router.openFiles(at: FilesTab.root) } label: { Label("文件", systemImage: "folder") }
                    Button { runner.saveState(reason: "asked from the Android page") } label: {
                        Label(runner.isSavingState ? "正在保存…" : "立即保存 Android", systemImage: "externaldrive.badge.checkmark")
                    }
                    .disabled(runner.isSavingState)
                } footer: {
                    Text("保存会完整保留 Android 当前状态，下次启动跳过引导。")
                }
            }

            Section("设置") {
                NavigationLink { PerformanceSettings() } label: { Label("性能", systemImage: "speedometer") }
                NavigationLink { InputSettings() } label: { Label("输入", systemImage: "hand.tap") }
                NavigationLink { NetworkSettings() } label: { Label("网络", systemImage: "globe") }
                NavigationLink { SavedMachineSettings() } label: { Label("已保存虚拟机", systemImage: "externaldrive") }
            }

            Section {
                Text("Android 完全模拟运行，因此比翻译层游戏慢。用于 Husk 无法直接运行的应用，如 Termux 或应用商店。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Android")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeInOut(duration: 0.2), value: status)
    }

    private var status: String {
        if running {
            if host.isReady { return "运行中" }
            return runner.setupMessage ?? (runner.bootProgress > 0 ? "启动中 · \(runner.bootProgress)%" : "启动中…")
        }
        switch guest.state {
        case .missing: return "尚未下载"
        case .downloading(_, let received, let total):
            return "下载中 · \(bytes(received)) / \(total > 0 ? bytes(total) : "…")"
        case .installing: return "安装中…"
        case .failed: return "出了点问题"
        case .ready: return Launcher.jitOn ? "可以启动" : "需要 JIT 才能启动"
        }
    }

    private var progress: Double? {
        if running, !host.isReady, runner.bootProgress > 0 { return Double(runner.bootProgress) / 100 }
        if !running, case .downloading(let p, _, _) = guest.state { return p }
        return nil
    }

    private var note: String? {
        guard !running else { return nil }
        switch guest.state {
        case .missing: return "Husk 的 Android 运行时约 760 MB。安装后还会下载 Android 系统本身。"
        case .failed(let message): return message
        default: return nil
        }
    }

    @ViewBuilder
    private var primary: some View {
        if running {
            if host.isReady {
                BigButton(title: "打开 Android", systemImage: "play.fill") { open() }
            } else {
                BigButton(title: "查看启动过程", systemImage: "eye", prominent: false) { open() }
            }
        } else {
            switch guest.state {
            case .missing:
                BigButton(title: "下载 Android", systemImage: "arrow.down.circle") {
                    // 在下载前先占用 JIT 区域：下载要一会，StikDebug 到结束时可能已松开。
                    JITBootstrap.prewarm()
                    guest.download()
                }
            case .downloading:
                BigButton(title: "取消下载", systemImage: "xmark", prominent: false) { guest.cancel() }
            case .installing:
                ProgressView().frame(height: 50)
            case .failed:
                BigButton(title: "重试", systemImage: "arrow.clockwise") { JITBootstrap.prewarm(); guest.download() }
            case .ready:
                if jit.busy {
                    HStack(spacing: 10) { ProgressView(); Text(jit.status ?? "正在开启 JIT…").foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity).frame(height: 50)
                } else {
                    BigButton(title: Launcher.jitOn ? "启动 Android" : "开启 JIT", systemImage: Launcher.jitOn ? "power" : "bolt.fill") {
                        router.startAndroid()
                    }
                }
            }
        }
    }

    private func open() {
        UserDefaults.standard.set(Date(), forKey: "husk.android.lastOpened")
        router.openGuest()
    }

    private func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }
}

/// 可用于弹窗展示的 URL。
struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.path }
}
