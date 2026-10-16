// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// 用大白话说明开启 JIT 的方式：StikJIT 已内置在 Husk 中，是推荐方式。
///
/// Android 和翻译层游戏都需要可写可执行内存，在 iOS 上这需要附着的调试器。
/// Husk 自己就能当这个调试器——App 内的 StikJIT，无需电脑也无需其他 App——
/// 因此凡 JIT 缺失处都先展示它，其他方式在一次点击之外。JIT 一旦开启，它收缩成一行字说明。
struct JITCard: View {
    @ObservedObject private var jit = JITCoordinator.shared
    /// 单行而非卡片：用于资源库，它在游戏列表上方而非占据整个页面。
    var compact = false

    private var isOn: Bool { JITBootstrap.ready }

    /// 此卡片提供的方式：Husk 自带 StikJIT 时（iOS 26 及以上）用它，否则用本机已有的方式——
    /// TrollStore、越狱——因为 StikJIT 在 iOS 26 之前无法运行。
    private var offered: JITMethod {
        if HuskBuiltInJIT.isAvailable { return .builtIn }
        let resolved = jit.resolvedMethod
        return resolved == .builtIn ? .builtIn : resolved
    }

    var body: some View {
        if compact {
            if !isOn { strip }
        } else {
            Group {
                if isOn { on } else { off }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    /// JIT 关闭状态下，开启方式，仅此而已。完整说明点一下文字即可看到。
    private var strip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.16), in: Circle())
                Button { jit.showSetup = true } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("JIT 未开启").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        Text(jit.busy ? (jit.status ?? "正在开启 JIT…") : "游戏需要它。\(offered == .builtIn ? "StikJIT" : offered.title) 将为你开启。")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if jit.busy {
                    ProgressView()
                } else {
                    Button {
                        if offered == .builtIn, HuskBuiltInJIT.isAvailable { jit.method = .builtIn }
                        jit.enable()
                    } label: {
                        Text("开启")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 30)
                            .background(Color.accentColor, in: Capsule())
                    }
                    .buttonStyle(CardButtonStyle())
                }
            }
            if let error = jit.error {
                Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var explanation: String {
        switch offered {
        case .trollStore:
            return "TrollStore 可以为 Husk 开启 JIT：它会打开 Husk 并启用，无需电脑。"
                 + "在 TrollStore 的设置中，必须开启 URL Scheme。"
        case .jailbreak:
            return "在越狱设备上 JIT 是一个设置项。在 Dopamine 中开启“允许 App 使用 JIT”，然后重新打开 Husk。"
        case .stikDebug:
            return "StikDebug 已安装，Husk 会打开它来开启 JIT。"
        default:
            return "StikJIT 已内置在 Husk 中。你可以在这里直接开启 JIT——无需电脑，也无需其他 App。"
                 + "游戏和 Android 都需要它。"
        }
    }

    private var buttonTitle: String {
        switch offered {
        case .trollStore: return "用 TrollStore 开启 JIT"
        case .jailbreak: return "如何允许 JIT"
        case .stikDebug: return "用 StikDebug 开启 JIT"
        default: return HuskBuiltInJIT.isAvailable ? "用 StikJIT 开启 JIT" : "开启 JIT"
        }
    }

    private var on: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("JIT 已开启").font(.headline)
                Text("游戏和 Android 可以运行了。").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .huskCard()
    }

    private var off: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.16)).frame(width: 44, height: 44)
                    Image(systemName: "bolt.fill").font(.title3).foregroundStyle(Color.accentColor)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(offered == .builtIn ? "StikJIT" : offered.title).font(.title3.weight(.semibold))
                    Text("开启 JIT").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            Text(explanation)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            if let why = HuskBuiltInJIT.unavailableReason {
                Text(why).font(.footnote).foregroundStyle(.orange)
            }

            if jit.busy {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(jit.status ?? "正在开启 JIT…").font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                Button {
                    // 此卡片提供的那个，即“自动”本会选的方式。
                    if offered == .builtIn, HuskBuiltInJIT.isAvailable { jit.method = .builtIn }
                    jit.enable()
                } label: {
                    HStack {
                        Spacer()
                        Label(buttonTitle, systemImage: "bolt.fill")
                            .font(.headline)
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if let error = jit.error {
                Text(error).font(.footnote).foregroundStyle(.orange)
            }

            Button { jit.showSetup = true } label: {
                Text("第一次使用？查看设置向导，或改用 StikDebug / TrollStore")
                    .font(.footnote)
            }
        }
        .padding(16)
        .huskCard()
    }
}
