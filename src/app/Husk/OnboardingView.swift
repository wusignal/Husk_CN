// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// Husk 在首次安装时向用户询问并记住的设置。
///
/// 故意做成带版本号的方案，而不是简单的“已看过”标记：后续版本如果新增了问题，
/// 需要能只问新问题，而不是把已有安装拖回整个流程。提高 `Onboarding.version`
/// 即可重新引导流程。
enum Onboarding {
    /// 当新增了已有安装必须回答的问题时，提高此版本号。
    static let version = 1

    private static let key = "husk.onboardingVersion"

    static var needed: Bool {
        UserDefaults.standard.integer(forKey: key) < version
    }

    static func complete() {
        UserDefaults.standard.set(version, forKey: key)
    }

    /// 在 JIT 可用时，App 一打开就自动启动 Android 客户机。
    static var autoStart: Bool {
        UserDefaults.standard.bool(forKey: "husk.autoStart")
    }
}

struct OnboardingView: View {
    let onDone: () -> Void

    @State private var page = 0
    @State private var autoStart = false
    @State private var landscape = UserDefaults.standard.bool(forKey: "husk.landscapeGuest")
    @State private var sound = UserDefaults.standard.bool(forKey: "husk.sound")
    @State private var autoSave =
        UserDefaults.standard.object(forKey: "husk.autoSave") as? Bool ?? true
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var jit = JITCoordinator.shared
    @State private var settingUpJIT = false

    private let pages = 4

    var body: some View {
        ZStack {
            Theme.backdrop

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    welcome.tag(0)
                    choices.tag(1)
                    jitPage.tag(2)
                    ready.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .sheet(isPresented: $settingUpJIT) { JITSetupFlow() }

                // 单个控件，始终位于同一位置。流程按钮自己来回移动会让人更难走完，
                // 而这又是每个人看到的第一屏。
                VStack(spacing: 12) {
                    HStack(spacing: 6) {
                        ForEach(0..<pages, id: \.self) { i in
                            Capsule()
                                .fill(i == page ? Theme.accent : Color.secondary.opacity(0.3))
                                .frame(width: i == page ? 18 : 6, height: 6)
                                .animation(.snappy, value: page)
                        }
                    }
                    Button {
                        if page < pages - 1 {
                            withAnimation(.snappy) { page += 1 }
                        } else {
                            save()
                            onDone()
                        }
                    } label: {
                        Text(page < pages - 1 ? "继续" : "开始使用 Husk")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 28)
                }
                .padding(.bottom, 28)
            }
        }
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(autoStart, forKey: "husk.autoStart")
        d.set(landscape, forKey: "husk.landscapeGuest")
        d.set(sound, forKey: "husk.sound")
        d.set(autoSave, forKey: "husk.autoSave")
        Onboarding.complete()
        HuskLog.log("ui", "setup complete: autoStart=\(autoStart) landscape=\(landscape) "
                        + "sound=\(sound) autoSave=\(autoSave)")
    }

    // MARK: 各引导页

    private var welcome: some View {
        VStack(spacing: 20) {
            Spacer()
            if let art = HuskAppIcon.current.preview(dark: scheme == .dark) {
                Image(uiImage: art)
                    .resizable().scaledToFit()
                    .frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                    .shadow(color: Theme.accent.opacity(0.35), radius: 22, y: 10)
            }
            Text("Husk").font(.system(size: 40, weight: .semibold, design: .rounded))
            Text("在你的 iPhone 上运行 Android 应用。")
                .font(.title3).foregroundStyle(.secondary)
            Text("Husk 运行一个完整的 Android 系统，并在其中打开 APK。"
               + "先回答几个问题——之后都可以在设置里修改。")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34).padding(.top, 4)
            Spacer()
        }
    }

    private var choices: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Husk 应该如何运行？")
                    .font(.title2.weight(.semibold))
                    .padding(.top, 34).padding(.bottom, 6)

                choice(icon: "bolt.fill", title: "启动时自动运行 Android",
                       detail: "JIT 可用时，Husk 一打开就启动客户机。关闭则由你手动启动。",
                       isOn: $autoStart)

                choice(icon: "rectangle.landscape.rotate", title: "横屏显示",
                       detail: "为 Android 使用横屏，游戏能正确铺满屏幕。竖屏应用则会留黑边。",
                       isOn: $landscape)

                choice(icon: "speaker.wave.2.fill", title: "声音",
                       detail: "添加音频设备。开启后 Android 无法休眠保存，每次启动都是冷启动。",
                       isOn: $sound)

                choice(icon: "externaldrive.badge.checkmark", title: "自动保存",
                       detail: "Android 启动稳定后自动保存虚拟机状态，下次启动几秒内即可恢复，而不必重新引导。",
                       isOn: $autoSave)
            }
            .padding(.horizontal, 20).padding(.bottom, 20)
        }
    }

    private func choice(icon: String, title: String, detail: String,
                        isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 9,
                                                                   style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn).labelsHidden().tint(Theme.accent)
        }
        .padding(16)
        .huskCard()
    }

    /// JIT 页面上显示的当前状态（如果已有）。
    private var jitState: String? {
        if JITBootstrap.ready { return "JIT 已开启。" }
        if jit.method == .stikDebug { return "Husk 将使用 StikDebug。" }
        if jit.method == .trollStore { return "Husk 将使用 TrollStore。" }
        switch jit.pairingSource {
        case .onDevice: return "已在本机完成配对。"
        case .imported: return "已导入配对文件。"
        case nil: return nil
        }
    }

    private var jitPage: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "bolt.fill")
                .font(.system(size: 54))
                .foregroundStyle(Theme.accent)
            Text("开启 JIT").font(.largeTitle.weight(.semibold))
            Text("Android 和翻译层游戏都需要 JIT，而在 iOS 上 JIT 只能由附着的调试器授予。"
               + "StikJIT 已内置于 Husk，是推荐方式：它在 App 内部直接开启 JIT，"
               + "无需电脑，也无需其他 App。StikDebug 和 TrollStore 同样可用。")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
            if let state = jitState {
                Label(state, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium)).foregroundStyle(.green)
            }
            Button(jitState == nil ? "立即设置 StikJIT" : "更改 JIT 设置") { settingUpJIT = true }
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .padding(.top, 4)
            Spacer()
        }
    }

    private var ready: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 62))
                .foregroundStyle(Theme.accent)
            Text("一切就绪").font(.largeTitle.weight(.semibold))
            Text("Android 启动时若 JIT 尚未开启，Husk 会用你选择的方式自动开启，"
               + "或引导你完成设置。随时可以在“设置 › JIT 与侧载”中更改。")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
            Spacer()
        }
    }
}
