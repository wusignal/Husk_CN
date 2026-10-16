// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// 设置页，布局仿照 iOS 设置 App：顶部是 App 卡片，下面是分组行，每行点进去是自己的页面。
/// 区分哪些属于 App 本身、哪些属于模拟器、以及这东西到底是什么。
struct SettingsTab: View {
    @AppStorage(AppWindows.defaultKey) private var multitask = false
    @AppStorage(CompatibilityStore.askKey) private var askCompat = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { AboutSettings() } label: { appCard }
                }

                Section {
                    row(JITSettings(), "bolt.fill", .yellow, "JIT 与侧载", "StikJIT 已内置——推荐方式")
                } header: {
                    Text("JIT")
                } footer: {
                    Text("Android 和翻译层游戏都需要 JIT。Husk 内置的 StikJIT 无需电脑即可开启。")
                }

                Section("通用") {
                    row(DiscoverView(), "sparkle.magnifyingglass", .mint, "发现", "在 F-Droid 等软件源中寻找应用")
                    row(LibrarySettings(), "square.grid.2x2.fill", .blue, "资源库", "你的应用及其图标")
                    row(PerformanceSettings(), "speedometer", .orange, "性能", "渲染器、声音")
                    row(AppearanceSettings(), "paintbrush.fill", .pink, "外观", "浅色/深色、强调色、App 图标")
                }

                Section {
                    Toggle(isOn: $multitask) {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("在窗口中打开应用")
                                Text("应用运行时仍可使用 Husk").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        } icon: {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.purple.gradient)
                                .frame(width: 30, height: 30)
                                .overlay {
                                    Image(systemName: "macwindow.on.rectangle")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.white)
                                }
                        }
                    }
                } header: {
                    Text("多任务")
                } footer: {
                    Text("应用和游戏在可移动、可缩放、可最小化到程序坞的窗口中打开，类似 LiveContainer 的多任务。"
                       + "每个应用可在自己的设置中单独覆盖此选项。")
                }

                Section {
                    Toggle(isOn: $askCompat) {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("询问游戏运行情况")
                                Text("每次更新后，每个游戏玩过一次后询问").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        } icon: {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.green.gradient)
                                .frame(width: 30, height: 30)
                                .overlay {
                                    Image(systemName: "list.bullet.clipboard")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.white)
                                }
                        }
                    }
                    Link(destination: CompatibilityStore.site) {
                        Label("兼容性列表", systemImage: "safari")
                    }
                } header: {
                    Text("兼容性")
                } footer: {
                    Text("游戏页面和商店会显示每个应用在所有人设备上的运行情况，数据来自 antiweb.lol。你的上报会附带"
                       + "设备型号、iOS 版本、Husk 构建号和 JIT 方式。")
                }

                Section("模拟器") {
                    row(InputSettings(), "hand.tap.fill", .indigo, "输入", "屏幕、触摸、键盘")
                    row(NetworkSettings(), "globe", .green, "网络", "互联网与已保存会话")
                    row(SavedMachineSettings(), "externaldrive.fill", .teal, "已保存虚拟机", "快照与自动保存")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("设置")
        }
    }

    private var appCard: some View {
        HStack(spacing: 14) {
            HuskMark(size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text("Husk").font(.title3.weight(.semibold))
                Text("版本 \(Bundle.main.version) · \(Bundle.main.commit)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func row<D: View>(_ destination: D, _ icon: String, _ tint: Color,
                              _ title: String, _ subtitle: String) -> some View {
        NavigationLink { destination } label: {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            } icon: {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.gradient)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                    }
            }
        }
    }
}

/// 仿系统样式的 Form。
private struct HuskForm: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationBarTitleDisplayMode(.inline)
    }
}

extension View {
    func huskForm() -> some View { modifier(HuskForm()) }
}

// MARK: - 资源库

struct LibrarySettings: View {
    @ObservedObject private var host = AndroidHost.shared
    @State private var working = false

    var body: some View {
        Form {
            Section {
                DetailRow(label: "应用数", value: "\(host.packages.count)", mono: false)
                DetailRow(label: "带图标",
                          value: "\(host.packages.filter { $0.iconPath != nil }.count)",
                          mono: false)
            } footer: {
                Text("应用列表已写入磁盘，因此在 Android 尚未启动完成时就能显示。")
            }

            Section {
                Button {
                    working = true
                    Task { await host.refreshPackages(); working = false }
                } label: {
                    Label(working ? "正在刷新…" : "从 Android 刷新",
                          systemImage: "arrow.clockwise")
                }
                .disabled(working || !host.isReady)

                Button {
                    AndroidHost.forgetIcons()
                    working = true
                    Task { await host.refreshPackages(); working = false }
                } label: {
                    Label("重新获取图标", systemImage: "photo.on.rectangle")
                }
                .disabled(working || !host.isReady)
            } footer: {
                Text("名称和图标来自 Android 自己的启动器，它保持自己绘制时的版本。"
                   + "重新获取会丢弃 Husk 本地的副本并再次请求。")
            }
        }
        .huskForm()
        .navigationTitle("资源库")
    }
}

// MARK: - 性能

struct PerformanceSettings: View {
    @ObservedObject private var runner = QemuRunner.shared
    @State private var gpuMode =
        UserDefaults.standard.object(forKey: "husk.gpuMode") as? Bool ?? true
    @State private var sound = UserDefaults.standard.bool(forKey: "husk.sound")
    @State private var soundDevice =
        UserDefaults.standard.object(forKey: "husk.soundDevice") as? Bool ?? true

    var body: some View {
        Form {
            Section {
                Picker("渲染器", selection: $gpuMode) {
                    Text("GPU").tag(true)
                    Text("CPU").tag(false)
                }
                .pickerStyle(.segmented)
                .onChange(of: gpuMode) { v in
                    UserDefaults.standard.set(v, forKey: "husk.gpuMode")
                    HuskLog.log("ui", v ? "GPU renderer selected" : "CPU renderer selected")
                }
            } header: {
                Text("渲染器")
            } footer: {
                Text(gpuMode
                     ? "Android 通过 Metal 在真实 GPU 上绘制——帧率约为四倍。这是默认选项。"
                     : "每个像素都由模拟的 CPU 绘制。慢得多，仅在 GPU 表现异常时才值得选。")
            }

            Section {
                DetailRow(label: "帧率",
                          value: runner.fps > 0
                                 ? String(format: "%.0f fps", runner.fps) : "—")
                DetailRow(label: "客户机屏幕",
                          value: "\(QemuRunner.lastGuestRes.w)×\(QemuRunner.lastGuestRes.h)")
            } header: {
                Text("当前状态")
            }

            Section {
                Toggle("声音", isOn: $sound)
                    .onChange(of: sound) { v in
                        UserDefaults.standard.set(v, forKey: "husk.sound")
                        HuskLog.log("ui", v ? "sound on" : "sound off")
                    }
                if sound {
                    Toggle("挂载音频设备", isOn: $soundDevice)
                        .onChange(of: soundDevice) { v in
                            UserDefaults.standard.set(v, forKey: "husk.soundDevice")
                        }
                }
            } header: {
                Text("声音")
            } footer: {
                Text("添加音频设备。挂载后 Android 无法保存——QEMU 拒绝为带音频设备的虚拟机拍快照——"
                   + "因此每次启动都是冷启动。无论开关，都需要一次冷启动。")
            }
        }
        .huskForm()
        .navigationTitle("性能")
    }
}

// MARK: - 输入

struct InputSettings: View {
    @State private var landscapeGuest =
        UserDefaults.standard.bool(forKey: "husk.landscapeGuest")
    @State private var customRes = UserDefaults.standard.bool(forKey: "husk.customRes")
    @State private var widthText = InputSettings.stored("husk.resWidth", 720)
    @State private var heightText = InputSettings.stored("husk.resHeight", 1280)

    /// 无需手动输入即可选的尺寸。故意只列这几个：这些是手机客户机实际使用的分辨率，
    /// 而非罗列所有曾出现过的面板。
    private static let presets: [(name: String, w: Int, h: Int)] = [
        ("小 — 360 × 800", 360, 800),
        ("高清 — 720 × 1280", 720, 1280),
        ("全高清 — 1080 × 1920", 1080, 1920),
        ("横屏高清 — 1280 × 720", 1280, 720),
        ("平板 — 1280 × 800", 1280, 800),
    ]

    private static func stored(_ key: String, _ fallback: Int) -> String {
        let v = UserDefaults.standard.integer(forKey: key)
        return String(v > 0 ? v : fallback)
    }

    /// 输入的数字实际生效的分辨率；若不是客户机可接受的尺寸则为空。
    private var effective: (w: Int, h: Int)? {
        QemuRunner.validResolution(w: Int(widthText) ?? 0, h: Int(heightText) ?? 0)
    }

    var body: some View {
        Form {
            Section {
                Picker("屏幕", selection: $landscapeGuest) {
                    Text("竖屏").tag(false)
                    Text("横屏").tag(true)
                }
                .pickerStyle(.segmented)
                .disabled(customRes)
                .onChange(of: landscapeGuest) { v in
                    UserDefaults.standard.set(v, forKey: "husk.landscapeGuest")
                    HuskLog.log("ui", v ? "guest panel will be landscape"
                                        : "guest panel will be portrait")
                }
            } header: {
                Text("屏幕")
            } footer: {
                Text(customRes
                     ? "自定义分辨率会直接设定屏幕形状，开启后此选项无效。横屏请输入较宽的尺寸。"
                     : "Android 运行中无法改变屏幕方向，因此竖屏上的横屏游戏会被压成窄条，显得很小。"
                       + "创建时即为横屏是它能铺满屏幕的唯一方式——竖屏应用则会留黑边。需要一次冷启动。")
            }

            Section {
                Toggle("自定义分辨率", isOn: $customRes)
                    .onChange(of: customRes) { v in
                        UserDefaults.standard.set(v, forKey: "husk.customRes")
                        store()
                        HuskLog.log("ui", v ? "custom resolution on: "
                                            + "\(widthText)x\(heightText)"
                                            : "custom resolution off")
                    }

                if customRes {
                    Picker("预设", selection: Binding(
                        get: { presetIndex },
                        set: { i in
                            guard i >= 0, i < Self.presets.count else { return }
                            widthText = String(Self.presets[i].w)
                            heightText = String(Self.presets[i].h)
                            store()
                        })) {
                        ForEach(0..<Self.presets.count, id: \.self) { i in
                            Text(Self.presets[i].name).tag(i)
                        }
                        Text("自定义").tag(-1)
                    }

                    HStack {
                        Text("宽度")
                        Spacer()
                        TextField("720", text: $widthText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.technical())
                            .frame(width: 90)
                            .onChange(of: widthText) { _ in store() }
                    }
                    HStack {
                        Text("高度")
                        Spacer()
                        TextField("1280", text: $heightText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.technical())
                            .frame(width: 90)
                            .onChange(of: heightText) { _ in store() }
                    }

                    if let size = effective {
                        DetailRow(label: "Android 将获得",
                                  value: "\(size.w) × \(size.h)")
                    } else {
                        Text("宽高都必须在 240 到 2560 之间。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }

                DetailRow(label: "当前运行", value: running)
            } header: {
                Text("分辨率")
            } footer: {
                Text("屏幕在虚拟机启动时构建，因此更改需要一次冷启动，下次保存会覆盖旧尺寸的虚拟机——"
                   + "改回来又要一次。尺寸自动取 8 的倍数。越大越慢：每个像素都由模拟的手机绘制。"
                   + "Android 的密度不随屏幕变化，所以更大的屏幕显示更多内容，而不是更大。")
            }

            Section {
                Text("触摸始终开启。键盘和旋转按钮在客户机屏幕底部的胶囊栏中；"
                   + "手柄和指针尚未接通。")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("控制")
            }
        }
        .huskForm()
        .navigationTitle("输入")
    }

    /// 客户机实际使用的面板尺寸，仅在有客户机时有意义：存储的值是上次启动的，直到新客户机启动。
    private var running: String {
        guard QemuRunner.shared.isRunning else { return "未启动" }
        return "\(QemuRunner.lastGuestRes.w) × \(QemuRunner.lastGuestRes.h)"
    }

    /// 输入数字对应哪个预设（若有）。
    private var presetIndex: Int {
        guard let size = effective else { return -1 }
        return Self.presets.firstIndex { $0.w == size.w && $0.h == size.h } ?? -1
    }

    private func store() {
        UserDefaults.standard.set(Int(widthText) ?? 0, forKey: "husk.resWidth")
        UserDefaults.standard.set(Int(heightText) ?? 0, forKey: "husk.resHeight")
    }
}

// MARK: - 网络

struct NetworkSettings: View {
    @State private var keepNetwork =
        UserDefaults.standard.object(forKey: "husk.keepNetwork") as? Bool ?? true

    var body: some View {
        Form {
            Section {
                Toggle("保存时保留网络连接", isOn: $keepNetwork)
                    .onChange(of: keepNetwork) { v in
                        UserDefaults.standard.set(v, forKey: "husk.keepNetwork")
                    }
            } footer: {
                Text(keepNetwork
                     ? "保存时关闭应用但保持 Android 框架运行，恢复后网络仍然可用。"
                     : "保存时连框架一起停止。会清除所有 GPU 资源，更稳定——但网络可能要到冷启动后才恢复。")
            }

            Section {
                Text("Android 通过 QEMU 自己网络中的虚拟网卡访问互联网。"
                   + "你手机网络上的任何设备都看不到客户机，客户机也看不到它们。")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("连接方式")
            }
        }
        .huskForm()
        .navigationTitle("网络")
    }
}

// MARK: - JIT 与侧载

struct JITSettings: View {
    @ObservedObject private var runner = QemuRunner.shared
    @ObservedObject private var jit = JITCoordinator.shared
    @State private var autoStart = Onboarding.autoStart
    @AppStorage(JITCoordinator.autoEnableKey) private var autoJIT = false
    @State private var keepAttached = JITBootstrap.keepDebuggerAttached

    private var pairingLabel: String {
        switch jit.pairingSource {
        case .onDevice: return "已在本机配对"
        case .imported: return "已导入文件"
        case nil: return "未设置"
        }
    }

    var body: some View {
        Form {
            Section {
                JITCard()
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Section {
                Picker("方式", selection: $jit.method) {
                    ForEach(JITMethod.allCases) { Text($0.title).tag($0) }
                }
                DetailRow(label: "StikDebug",
                          value: JITBootstrap.isStikDebugInstalled ? "已安装" : "未找到", mono: false)
                DetailRow(label: "TrollStore",
                          value: JITBootstrap.isTrollStoreInstalled ? "已安装" : "未找到", mono: false)
                DetailRow(label: "用 TrollStore 安装",
                          value: JITBootstrap.isInstalledWithTrollStore ? "是" : "否", mono: false)
                DetailRow(label: "越狱",
                          value: JITBootstrap.debuggedAtLaunch ? "已允许 App 使用 JIT"
                               : JITBootstrap.isJailbroken ? "已检测到" : "未检测到", mono: false)
                DetailRow(label: "内置配对", value: pairingLabel, mono: false)
                Button {
                    jit.showSetup = true
                } label: {
                    Label("设置 JIT", systemImage: "wand.and.stars")
                }
            } header: {
                Text("其他开启 JIT 的方式")
            } footer: {
                Text(jit.method == .automatic
                     ? jit.automaticDescription + " 内置 StikJIT 需要 iOS 26、LocalDevVPN 和配对文件，iOS 27 上 Husk 可自行生成。"
                     : HuskBuiltInJIT.unavailableReason ?? "内置 StikJIT 需要 LocalDevVPN 和配对文件，iOS 27 上 Husk 可自行生成。")
            }

            Section {
                DetailRow(label: "调试器",
                          value: JITBootstrap.isDebuggerAttached ? "已附着" : "未附着",
                          mono: false)
                DetailRow(label: "可执行内存",
                          value: JITBootstrap.isLive ? "已授予" : "未获取", mono: false)
                // 两条路径分别命名。任一即可，当有人反馈“JIT 不工作”时，这两行就是全部诊断依据。
                DetailRow(label: "陷阱服务",
                          value: husk_ios_jit_self_route() != nil ? "不需要"
                               : JITBootstrap.prewarmed ? "正在响应" : "未响应",
                          mono: false)
                if let route = husk_ios_jit_self_route() {
                    DetailRow(label: "由 Husk 提供",
                              value: String(cString: route) == "MAP_JIT" ? "MAP_JIT（TrollStore 权限）" : "普通内存（已调试或已越狱）",
                              mono: false)
                }
                // 仅使用缓存结果：在视图 body 中运行探测可能冻结 App（见 JITBootstrap.mapJITWorks）。
                DetailRow(label: "MAP_JIT",
                          value: JITBootstrap.deviceEnforcesTXM ? "未使用（TXM）"
                               : JITBootstrap.mapJITResult.map { $0 ? "可执行" : "被拒绝" }
                                 ?? "未测试",
                          mono: false)
                DetailRow(label: "设置后调试器",
                          value: JITBootstrap.detached ? "已分离" : "已附着",
                          mono: false)
                if let why = JITBootstrap.lastFailure {
                    Text(why).font(.caption).foregroundStyle(.orange)
                }
                if !JITBootstrap.ready {
                    Button {
                        jit.enable()
                    } label: {
                        Label("用 \(jit.resolvedMethod.title) 开启 JIT", systemImage: "bolt.fill")
                    }
                    .disabled(jit.busy)
                    Button {
                        _ = JITBootstrap.requestTrollStoreAttach()
                    } label: {
                        Label("用 TrollStore 开启 JIT", systemImage: "sparkles")
                    }
                }
            } header: {
                Text("JIT")
            } footer: {
                Text("Husk 需要可写可执行的内存，在 iOS 上这需要附着的调试器。获取方式有两种："
                   + "服务陷阱请求的调试器，或 MAP_JIT 映射——内核允许任何被调试进程使用。任一即可。"
                   + "具体哪种可用取决于设备和 iOS 版本，因此 Husk 两个都测试，而不是凭空假设。")
            }

            Section {
                Toggle("启动时自动开启 JIT", isOn: $autoJIT)
                    .disabled(!HuskBuiltInJIT.isAvailable)
            } footer: {
                Text(HuskBuiltInJIT.isAvailable
                     ? "每次 Husk 在没有 JIT 的情况下打开时，会请求内置 StikJIT 开启 JIT，无需点按即可让游戏就绪。需先完成一次 StikJIT 设置（配对）。"
                     : "需要内置 StikJIT，仅在 iOS 26 及以上可用。")
            }

            Section {
                Toggle("启动时自动运行 Android", isOn: $autoStart)
                    .onChange(of: autoStart) { v in
                        UserDefaults.standard.set(v, forKey: "husk.autoStart")
                    }
            } footer: {
                Text("JIT 可用时，Husk 一打开就启动客户机。")
            }

            Section {
                Toggle("保持调试器附着", isOn: $keepAttached)
                    .onChange(of: keepAttached) { v in JITBootstrap.keepDebuggerAttached = v }
            } footer: {
                Text("默认关闭。Husk 在拿到 JIT 区域后会立即分离 StikDebug，因为被 iOS 挂起的调试器会在下次需要它时卡住整个 App。"
                   + "仅在需要收集 StikDebug 自身日志时才开启。")
            }

            Section {
                Text("APK 通过资源库的 + 按钮或“文件”标签页安装。拆分包——基础 APK 加配置分片——必须一起选择；"
                   + "只装基础包会因缺少原生库而失败。")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("侧载")
            }
        }
        .huskForm()
        .navigationTitle("JIT 与侧载")
    }
}

// MARK: - 已保存虚拟机

struct SavedMachineSettings: View {
    @ObservedObject private var runner = QemuRunner.shared
    @State private var autoSave =
        UserDefaults.standard.object(forKey: "husk.autoSave") as? Bool ?? true
    @State private var useSnapshot =
        UserDefaults.standard.object(forKey: "husk.downloadSnapshot") as? Bool ?? true
    @State private var askWhichToDelete = false
    @State private var deleteResult: String?
    @AppStorage(GuestImage.askUpdatesKey) private var askUpdates = true

    var body: some View {
        Form {
            Section {
                Toggle("自动保存", isOn: $autoSave)
                    .onChange(of: autoSave) { v in
                        UserDefaults.standard.set(v, forKey: "husk.autoSave")
                        HuskLog.log("ui", v ? "automatic saving on" : "automatic saving off")
                    }
                Button {
                    QemuRunner.shared.saveState(reason: "asked from settings")
                } label: {
                    Label(runner.isSavingState ? "正在保存…" : "立即保存",
                          systemImage: "externaldrive.badge.checkmark")
                }
                .disabled(runner.isSavingState)
            } footer: {
                Text("Husk 会恢复已保存的虚拟机而不是重新引导，几秒即可进入而非几分钟。写入时画面会冻结。"
                   + "关闭后，任何情况下都不会自动保存——包括安装之后。")
            }

            Section {
                Button(role: .destructive) { askWhichToDelete = true } label: {
                    Label("删除已保存虚拟机", systemImage: "trash")
                }
                .disabled(!QemuRunner.shared.hasSnapshot)
                if let deleteResult {
                    Text(deleteResult).font(.caption).foregroundStyle(.secondary)
                }
            } footer: {
                Text(QemuRunner.shared.hasSnapshot
                     ? "当前已保存："
                     + ((QemuRunner.shared.snapshotDisplay ?? "sw").contains("gl")
                        ? "GPU" : "软件") + "。"
                     : "没有已保存内容，Android 将冷启动。")
            }

            Section {
                Toggle("下载预启动快照", isOn: $useSnapshot)
                    .onChange(of: useSnapshot) { v in
                        UserDefaults.standard.set(v, forKey: "husk.downloadSnapshot")
                    }
            } footer: {
                Text("首次下载约多占 2 GB。它是在软件渲染器下捕获的，因此 GPU 模式不使用它——GPU 会冷启动一次，然后保存自己的快照。")
            }

            Section {
                Toggle("询问 Android 更新", isOn: $askUpdates)
            } footer: {
                Text("发布新的 Android 镜像或快照时，Husk 会询问一次是否下载。在 Android 尚未下载前不会询问。")
            }
        }
        .huskForm()
        .navigationTitle("已保存虚拟机")
        .confirmationDialog("删除哪个已保存虚拟机？", isPresented: $askWhichToDelete,
                            titleVisibility: .visible) {
            Button("GPU 虚拟机", role: .destructive) { forget("gl", "GPU") }
            Button("软件虚拟机", role: .destructive) { forget("sw", "软件") }
            Button("取消", role: .cancel) { }
        } message: {
            Text("Android 将冷启动一次，然后保存新的。")
        }
    }

    private func forget(_ mode: String, _ name: String) {
        if QemuRunner.shared.forgetSnapshot(mode: mode) {
            deleteResult = "已删除\(name)虚拟机。下次启动将冷启动。"
        } else {
            deleteResult = "没有已保存的\(name)虚拟机，未删除任何内容。"
        }
    }
}

// MARK: - 外观

struct AppearanceSettings: View {
    @State private var appIcon = HuskAppIcon.current
    @AppStorage(Theme.Appearance.key) private var appearance = Theme.Appearance.system
    @AppStorage(Holiday.key) private var holiday = true
    @ObservedObject private var theme = AppTheme.shared
    @Environment(\.colorScheme) private var scheme
    @State private var custom: Color = AppTheme.shared.accentColor

    private let iconColumns = [GridItem(.adaptive(minimum: 92), spacing: 14)]

    var body: some View {
        Form {
            Section {
                Picker("外观", selection: $appearance) {
                    ForEach(Theme.Appearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: appearance) { v in
                    HuskLog.log("ui", "appearance: \(v.rawValue)")
                }
                Toggle("节日装饰", isOn: $holiday)
            } header: {
                Text("主题")
            } footer: {
                Text("跟随系统：白天浅色，夜晚深色。客户机自己的屏幕始终为深色——那只是另一台手机的画面。")
            }

            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 14) {
                    ForEach(AppTheme.presets) { preset in
                        Button {
                            theme.accentColor = preset.color
                            custom = preset.color
                        } label: {
                            swatch(preset.color, selected: preset.color.themeHex == theme.accentColor.themeHex)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(preset.name)
                    }
                }
                .padding(.vertical, 6)

                ColorPicker("自定义颜色", selection: $custom, supportsOpacity: false)
                    .onChange(of: custom) { theme.accentColor = $0 }
            } header: {
                Text("强调色")
            } footer: {
                Text("为整个 App 的按钮、开关和选中状态着色。")
            }

            Section {
                LazyVGrid(columns: iconColumns, spacing: 14) {
                    ForEach(HuskAppIcon.allCases) { icon in
                        Button {
                            appIcon = icon
                            HuskAppIcon.apply(icon)
                        } label: {
                            VStack(spacing: 8) {
                                if let art = icon.preview(dark: scheme == .dark) {
                                    Image(uiImage: art)
                                        .resizable().scaledToFit()
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(appIcon == icon ? Color.accentColor : .clear, lineWidth: 3))
                                }
                                Text(icon.title)
                                    .font(.caption)
                                    .foregroundStyle(appIcon == icon ? Color.accentColor : .primary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text("App 图标")
            } footer: {
                Text("自动跟随系统外观——浅色、深色和着色。其他选项则固定为某一种外观。"
                   + "更改后 iOS 会弹出自己的确认框，该提示无法关闭。")
            }
        }
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func swatch(_ color: Color, selected: Bool) -> some View {
        Circle()
            .fill(color)
            .frame(width: 34, height: 34)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.9), lineWidth: selected ? 2 : 0).padding(-4))
            .overlay {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(color.isLight ? .black : .white)
                }
            }
            .frame(maxWidth: .infinity)
    }
}

// MARK: - 关于

struct AboutSettings: View {
    @ObservedObject private var runner = QemuRunner.shared
    @State private var showLogs = false
    @AppStorage(TranslationLayer.devInfoKey) private var devInfo = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    HuskMark(size: 84)
                    Text("Husk").font(.title2.weight(.semibold))
                    Text("版本 \(Bundle.main.version)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .listRowBackground(Color.clear)
            }

            Section {
                LabeledContent("构建号", value: Bundle.main.commit)
                LabeledContent("客户机镜像", value: GuestImage.imageVersion)
                LabeledContent("渲染器",
                               value: runner.displayKind == .gl ? "GPU"
                                    : runner.displayKind == .software ? "CPU"
                                    : "未启动")
            }

            Section {
                Toggle(isOn: $devInfo) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("开发者信息")
                        Text("在 Android 翻译层界面显示技术细节：库报告、设备检查和运行日志。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if devInfo {
                    NavigationLink { TLChecksView() } label: {
                        Label("设备检查", systemImage: "stethoscope")
                    }
                    NavigationLink { MassTestView() } label: {
                        Label("批量测试", systemImage: "square.stack.3d.down.forward")
                    }
                }
                Button { showLogs = true } label: {
                    Label("打开控制台", systemImage: "terminal")
                }
            } footer: {
                Text("Husk 在你的 iPhone 上用真实 Android 系统运行未修改的 Android APK。"
                   + "控制台显示 Husk 的实时日志、客户机串口输出和 QEMU 自身输出——诊断任何问题都靠这三份文件。")
            }
        }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLogs) { LogView() }
    }
}

extension Bundle {
    var version: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }
    var commit: String {
        (infoDictionary?["HuskBuildCommit"] as? String) ?? "?"
    }
}
