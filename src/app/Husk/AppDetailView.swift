// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// 从主页或资源库推入的页面：游戏页面、游戏设置或技术细节、Android 应用页面，或 Android 系统本身。
enum LibraryRoute: Hashable {
    case android(AndroidHost.Package)
    case game(String)
    case gameSettings(String)
    case gameReport(String)
    case androidSystem
    case ps4(String)              // PS4 游戏，按 title ID
}

/// 标签页及其导航栈由此处统一调度。
///
/// 一个页面可以把你带到别处——应用页面提供它的文件入口，主页的“查看全部”打开资源库——
/// 而导航栈无法从外部推入，除非有地方记住路径。这里就是那个地方。它还承载只有根视图能做的两件事：
/// 显示 Android 的屏幕，以及启动 Android。
@MainActor final class Router: ObservableObject {
    static let shared = Router()

    @Published var tab: HuskTab = .home
    @Published var home: [LibraryRoute] = []
    @Published var library: [LibraryRoute] = []
    @Published var libraryFilter: LibraryFilter = .all
    /// 下载页，以弹窗形式：主页的下载磁贴打开它。
    @Published var showDownloads = false
    /// Android 的存储，以弹窗形式覆盖在当前页面上。
    @Published var showFiles = false
    /// 推到文件根目录之上的目录。
    @Published var files: [String] = []
    /// 本次 Husk 运行中 Android 已启动。
    @Published var androidStarted = false
    /// Android 启动后立即打开的 Android 应用：在 Android 关闭时从其页面请求。
    @Published var pendingAndroidLaunch: String?

    /// 页面就绪后立即启动的游戏：Husk 为切换到它而关闭的那个（见 `switchTo`）。
    @Published var autoPlay: String?

    private static let switchKey = "husk.switchToGame"

    /// 每次 Husk 运行只能加载一个游戏。关闭 Husk 去玩另一个会记住是哪个，下次启动打开它的页面并启动，
    /// 所以切换流程是：关闭、打开、开玩。
    func switchTo(_ appID: String) { UserDefaults.standard.set(appID, forKey: Self.switchKey) }

    /// 启动时：Husk 为切换而关闭时所在的游戏，打开并启动它。
    func resumeSwitch() {
        guard let id = UserDefaults.standard.string(forKey: Self.switchKey) else { return }
        UserDefaults.standard.removeObject(forKey: Self.switchKey)
        HuskLog.log("ui", "opening \(id), which Husk was closed to switch to")
        tab = .library
        library = id.hasPrefix("ps4:") ? [.ps4(String(id.dropFirst(4)))] : [.game(id)]
        autoPlay = id
    }

    /// 显示 Android 自己的屏幕。由根视图设置。
    var openGuest: () -> Void = {}
    /// 启动 Android；若 JIT 未开则先开启。由根视图设置。
    var startAndroid: () -> Void = {}

    /// 从任意位置显示 Android 存储中的某个目录。
    func openFiles(at path: String) {
        files = path == FilesTab.root ? [] : [path]
        showFiles = true
    }

    func showLibrary(_ filter: LibraryFilter) {
        libraryFilter = filter
        tab = .library
    }

    /// 选择 APK 或整包；Husk 随后询问放到哪里。
    func addSomething() {
        HuskFilePicker.present { urls in IncomingFiles.shared.receive(urls) }
    }
}

/// 一个应用：它是什么，以及值得对它做的操作。
struct AppDetailView: View {
    let app: AndroidHost.Package
    let onOpenGuest: () -> Void

    @ObservedObject private var host = AndroidHost.shared
    @ObservedObject private var router = Router.shared
    @Environment(\.dismiss) private var dismiss
    @State private var confirmUninstall = false

    private var live: AndroidHost.Package {
        host.packages.first { $0.name == app.name } ?? app
    }
    private var canOpen: Bool { host.isReady && host.busy == nil }

    var body: some View {
        List {
            Section {
                header
                Button {
                    host.launch(app.name) { onOpenGuest() }
                } label: {
                    HStack {
                        Spacer()
                        Label(canOpen ? "启动" : "正在启动 Android…",
                              systemImage: canOpen ? "play.fill" : "hourglass")
                            .font(.headline)
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canOpen)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } footer: {
                if !host.isReady { Text("Android 就绪后立即打开。") }
            }

            Section {
                LabeledContent("版本", value: live.version ?? "—")
                LabeledContent("大小", value: live.sizeBytes.map(Self.bytes) ?? "—")
                LabeledContent("上次使用", value: live.lastUsed.map(Self.when) ?? "从未在 Husk 中使用")
            }

            Section {
                Button { router.openFiles(at: "/sdcard/Android/data/\(app.name)") } label: {
                    Label("在文件中打开", systemImage: "folder")
                }
                Button { appInfo() } label: {
                    Label("应用信息", systemImage: "info.circle")
                }
                .disabled(!canOpen)
                Button(role: .destructive) { confirmUninstall = true } label: {
                    Label("卸载", systemImage: "trash")
                }
                .disabled(!canOpen)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(live.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { menu } }
        .confirmationDialog("卸载 \(live.label)？", isPresented: $confirmUninstall,
                            titleVisibility: .visible) {
            Button("卸载", role: .destructive) {
                host.uninstall(app.name)
                dismiss()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("其数据将一并删除。之后请保存 Android，否则更改会在下次启动时丢失。")
        }
    }

    // MARK: 组件

    private var menu: some View {
        Menu {
            Button {
                UIPasteboard.general.string = app.name
            } label: { Label("复制包名", systemImage: "doc.on.doc") }
            Button { appInfo() } label: {
                Label("在 Android 设置中显示", systemImage: "gearshape")
            }
            .disabled(!canOpen)
            Divider()
            Button(role: .destructive) { confirmUninstall = true } label: {
                Label("卸载", systemImage: "trash")
            }
            .disabled(!canOpen)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            AppIcon(path: live.iconPath, size: 76)
            VStack(alignment: .leading, spacing: 6) {
                Text(live.label)
                    .font(.title2.weight(.bold))
                    .lineLimit(2)
                Text(live.name)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    if let c = live.category { Tag(text: c) }
                    if let b = live.bitness { Tag(text: b) }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    /// Android 自己的应用页面——权限、存储、强制停止。
    /// 这是 Android 已有的界面，Husk 不应重新实现。
    private func appInfo() {
        let pkg = app.name
        DispatchQueue.global(qos: .userInitiated).async {
            _ = try? GuestBridge.shared.shell(
                "am start -a android.settings.APPLICATION_DETAILS_SETTINGS "
              + "-d package:\(pkg)", timeout: 30)
        }
        onOpenGuest()
    }

    // MARK: 格式化

    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    static func when(_ date: Date) -> String {
        let f = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            f.dateFormat = "'今天,' h:mm a"
        } else if Calendar.current.isDateInYesterday(date) {
            f.dateFormat = "'昨天,' h:mm a"
        } else {
            f.dateStyle = .medium
            f.timeStyle = .none
        }
        return f.string(from: date)
    }
}
