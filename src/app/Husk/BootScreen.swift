// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// Husk 在为你启动 Android 时显示的屏幕。
///
/// 在此之前，"启动时自动开始"会把你直接扔进资源库，但那里的应用还打不开，
/// 顶部还有一条提示解释原因——这等于一个让你在它前面干等的界面。引导就是引导：
/// 它有自己的屏幕，显示进度，并在工作时和你说说话。那些趣味短语之所以存在，
/// 是因为两分钟的进度条会让人怀疑是不是卡死了。
struct BootScreen: View {
    let onSkip: () -> Void

    @ObservedObject private var runner = QemuRunner.shared
    @ObservedObject private var host = AndroidHost.shared

    @State private var phrase = 0
    @State private var began = Date()
    @State private var now = Date()
    @State private var pulse = false
    /// bootProgress 上次变化的时间，用于让进度条在里程碑之间缓慢推进。
    @State private var lastStep = Date()

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let rotate = Timer.publish(every: 3.4, on: .main, in: .common).autoconnect()

    /// 按顺序显示而非随机：前两句在用户还盯着屏幕时出现，
    /// 笑话不应在信息本身重复之前重复。
    private static let phrases = [
        "准备好迎接精彩时刻",
        "正在唤醒 Android",
        "教 iPhone 说 Android 语言",
        "这可是一整个操作系统，请耐心等待",
        "应用作者：Levi",
        "喜欢的话请给仓库点个 Star",
        "正在逐块翻译 arm64 指令",
        "别担心，它没有卡死",
        "正在解包客户机",
        "等待是值得的",
        "正在与 JIT 协商",
        "马上就好",
    ]

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                HuskMark(size: 96)
                    .shadow(color: Theme.accent.opacity(pulse ? 0.45 : 0.15),
                            radius: pulse ? 34 : 18, y: 10)
                    .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                               value: pulse)
                    .onAppear { pulse = true }

                Text("HUSK")
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(9)
                    .foregroundStyle(Theme.text)
                    .padding(.leading, 9)
                    .padding(.top, 18)

                // 滚动的那句文案。按索引切换，让一句淡入下一句而非硬切。
                Text(Self.phrases[phrase % Self.phrases.count])
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
                    .frame(height: 42)
                    .padding(.horizontal, 30)
                    .id(phrase)
                    .transition(.opacity)
                    .padding(.top, 10)

                progress
                    .padding(.horizontal, 44)
                    .padding(.top, 6)

                Spacer()

                // Android 自身正在做什么，小字显示在最下方。
                // 趣味短语用来打发时间；这一行才是真实状态。
                Text(runner.setupMessage ?? host.status)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textDim.opacity(0.75))
                    .lineLimit(1)
                    .padding(.horizontal, 30)

                // 逃生口，但不是邀请入口：只在等待不再新鲜后才出现。
                if now.timeIntervalSince(began) > 8 {
                    Button("边下边用 Husk", action: onSkip)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textDim)
                        .padding(.top, 14)
                        .transition(.opacity)
                }
            }
            .padding(.bottom, 26)
        }
        .onReceive(tick) { now = $0 }
        .onChange(of: runner.bootProgress) { _ in lastStep = Date() }
        .onReceive(rotate) { _ in
            withAnimation(.easeInOut(duration: 0.45)) { phrase += 1 }
        }
        .animation(.easeInOut(duration: 0.3), value: now.timeIntervalSince(began) > 8)
    }

    private var progress: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceHigh)
                    Capsule().fill(Theme.accent)
                        .frame(width: geo.size.width * fraction)
                        .animation(.snappy(duration: 0.4), value: fraction)
                }
            }
            .frame(height: 5)

            HStack {
                Text(shown > 0 ? "\(shown)%" : "启动中")
                    .font(.technical(12, weight: .medium))
                    .foregroundStyle(Theme.accent)
                Spacer()
                if let left = remaining {
                    Text(left)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textDim)
                }
            }
        }
    }

    private var fraction: CGFloat {
        // 绝不为零：空进度条看起来像卡死，而不是刚开始，
        // 而客户机最初几秒什么也不会输出。
        max(CGFloat(shown) / 100, 0.03)
    }

    /// 显示出的进度。真实数字只在出现里程碑行时跳动，冷启动后期这些里程碑之间相隔数分钟。
    /// 在间隔内，进度条每 30 秒增加 1%。它停在距下一里程碑还差一格的位置，且绝不超过 95%，
    /// 这样它永远不会声称进度超过客户机实际进度。
    private var shown: Int {
        let real = runner.bootProgress
        guard real > 0, real < 100, !QemuRunner.didRestore else { return real }
        let next = QemuRunner.bootMilestones.map { $0.2 }.first { $0 > real } ?? 100
        let creep = Int(now.timeIntervalSince(lastStep) / 30)
        return max(real, min(real + creep, next - 1, 95))
    }

    /// 基于本次启动自身节奏的估计，而非某人敲进去的数字。
    /// 在曲线足够计算之前不显示，临近结束时也再次隐藏——那时猜错最烦人。
    private var remaining: String? {
        let done = Double(runner.bootProgress)
        // 越过 zygote 后，剩余时间主要是应用编译，早期节奏对它没有参考意义。
        // 估计曾连续十分钟都在说"大约一分钟"，所以改为显示已用时间。
        if done >= 58, !QemuRunner.didRestore {
            let mins = Int(now.timeIntervalSince(QemuRunner.bootStarted) / 60)
            return mins < 1 ? "首次启动需 5–15 分钟"
                            : "已用 \(mins) 分钟 · 首次启动需 5–15 分钟"
        }
        guard done >= 8, done <= 92 else { return nil }
        let elapsed = now.timeIntervalSince(began)
        guard elapsed > 6 else { return nil }
        let total = elapsed / (done / 100)
        let left = total - elapsed
        guard left > 2, left < 15 * 60 else { return nil }
        if left < 90 {
            let rounded = Int((left / 5).rounded()) * 5
            return "约 \(max(rounded, 5)) 秒后完成"
        }
        return "约 \(Int((left / 60).rounded())) 分钟后完成"
    }
}
