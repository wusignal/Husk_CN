// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UIKit

/// "那个游戏把 Husk 搞崩了"：下次启动时发现、解释，并方便一键发送。
///
/// 崩溃的游戏会把 Husk 一起带走——它跑在 Husk 自己的进程里——所以发生的当下什么都显示不了。
/// 改为在游戏启动时写一个标记，正常关闭游戏时删除。下次启动时标记还在，就说明游戏没能正常退出：
/// Husk 展示从上一次运行日志（保留为 husk-prev.log）中已知的信息，并提供完整报告供分享。
@MainActor
final class CrashReport: ObservableObject {
    static let shared = CrashReport()

    struct Report: Identifiable {
        let id = UUID()
        let game: String
        let appID: String
        let cause: Cause
        let when: Date?
        /// 上一次运行的末尾若干行，用于报告页。
        let excerpt: [String]
    }

    enum Cause {
        case signal(Int)        // 崩溃处理程序记录到的致命信号
        case startFailed        // 运行时告知游戏无法启动，此后 Husk 退出
        case unknown            // 无记录：内存不足（iOS 无声结束 App），或 Husk 被手动上滑关闭
        case diagnosed(AppDiagnosis)    // 运行日志说明了原因（AppDiagnosis）

        var title: String {
            switch self {
            case .signal: return "游戏崩溃了"
            case .startFailed: return "游戏无法启动"
            case .unknown: return "游戏运行期间 Husk 被关闭"
            case .diagnosed(let d): return d.title
            }
        }
        var detail: String {
            switch self {
            case .signal(let s):
                let name = [11: "SIGSEGV，非法内存访问", 6: "SIGABRT，游戏或某个库主动放弃",
                            4: "SIGILL，本机 CPU 不支持的指令", 8: "SIGFPE，算术错误",
                            12: "SIGSYS，iOS 不允许的系统调用"][s] ?? "信号 \(s)"
                return "它以 \(name) 终止。报告里有本次运行的完整日志。"
            case .startFailed:
                return "运行时无法启动它。报告里说明了缺少哪个部分。"
            case .unknown:
                return "没有任何记录，通常意味着 iOS 因内存不足结束了 Husk，或 Husk 被从应用切换器上滑关闭。"
            case .diagnosed(let d):
                return d.detail
            }
        }
    }

    @Published var pending: Report?

    private static var docs: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private static var marker: URL { docs.appendingPathComponent("running-game.json") }
    static var previousLogURL: URL { docs.appendingPathComponent("husk-prev.log") }

    // MARK: 运行标记

    private static var running: TLApp?
    private static var observers: [NSObjectProtocol] = []

    /// 游戏正在启动：如果 Husk 在 `gameEnded` 之前结束，下次启动会提示。
    ///
    /// 但 Husk 在后台时不算：iOS 在需要内存时会无声结束后台 App，那不是游戏的问题。
    /// 标记在 Husk 离开屏幕时移除，回到屏幕时恢复。
    static func gameStarted(_ app: TLApp) {
        running = app
        writeMarker()
        if observers.isEmpty {
            let nc = NotificationCenter.default
            observers.append(nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
                try? FileManager.default.removeItem(at: marker)
            })
            observers.append(nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
                writeMarker()
            })
        }
    }

    private static func writeMarker() {
        guard let app = running else { return }
        let info: [String: Any] = ["id": app.id, "label": app.label, "time": Date().timeIntervalSince1970]
        if let data = try? JSONSerialization.data(withJSONObject: info) { try? data.write(to: marker, options: .atomic) }
    }

    /// 游戏已正常关闭。
    static func gameEnded() {
        running = nil
        try? FileManager.default.removeItem(at: marker)
    }

    /// 启动时：上次 Husk 结束时是否有游戏在运行？
    func checkPreviousRun() {
        guard let data = try? Data(contentsOf: Self.marker),
              let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        try? FileManager.default.removeItem(at: Self.marker)
        let lines = ((try? String(contentsOf: Self.previousLogURL, encoding: .utf8)) ?? "")
            .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        var cause = Cause.unknown
        if let fatal = lines.last(where: { $0.contains("*** FATAL SIGNAL") }),
           let n = fatal.split(separator: " ").compactMap({ Int($0) }).first {
            cause = .signal(n)
        } else if lines.contains(where: { $0.contains("the game could not be started") || $0.contains("native: launch refused") }) {
            cause = .startFailed
        }
        if let d = AppDiagnosis.fromLog(lines.joined(separator: "\n")) { cause = .diagnosed(d) }
        let time = (info["time"] as? Double).map { Date(timeIntervalSince1970: $0) }
        pending = Report(game: info["label"] as? String ?? "一个游戏", appID: info["id"] as? String ?? "",
                         cause: cause, when: time, excerpt: Array(Self.interesting(lines).suffix(14)))
        HuskLog.log("crash", "\(pending!.game) did not close normally last run: \(cause.title)")
        switch cause {
        case .signal: GameStatusStore.shared.record(pending!.appID, .crashed)
        case .startFailed: GameStatusStore.shared.record(pending!.appID, .failed)
        case .unknown: break
        case .diagnosed(let d): GameStatusStore.shared.record(pending!.appID, .crashed, diagnosis: d)
        }
    }

    /// 日志中值得一看的行：运行时和崩溃处理程序的，而非 JIT 的日常记录。
    private static func interesting(_ lines: [String]) -> [String] {
        lines.filter { l in
            !l.contains("csops status") && !l.contains("[husk-jit]") && !l.contains("[jit]") && !l.contains("[guest]")
                && !l.contains("[boot]") && !l.contains("[prev]")
        }
    }

    // MARK: 报告

    /// 汇总成一个文本文件：发生了什么、本机信息、以及那次结束运行的两份日志。
    static func writeReport(_ r: Report) -> URL? {
        let info = Bundle.main.infoDictionary ?? [:]
        var text = """
        Husk 崩溃报告
        =================
        游戏     : \(r.game)
        情况     : \(r.cause.title)
        开始时间 : \(r.when.map { ISO8601DateFormatter().string(from: $0) } ?? "?")
        Husk     : \(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?")) \(info["HuskBuildCommit"] as? String ?? "")
        设备     : \(HuskLog.deviceModel), \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)

        """
        if let app = TranslationLayerStore.shared.apps.first(where: { $0.id == r.appID }) {
            text += "包名     : \(app.packageName ?? "?")\n"
            text += "APK 文件 : \(app.apks.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "))\n"
            text += "引擎     : \(app.report?.nativeEngine.map { "\($0)" } ?? "?")\n"
        }
        text += "\n---- 本次运行的 husk.log ----\n"
        text += (try? String(contentsOf: previousLogURL, encoding: .utf8)) ?? "(未保存)\n"
        text += "\n---- 本次运行的原生输出 ----\n"
        text += (try? String(contentsOf: HuskLog.previousNativeLogURL, encoding: .utf8)) ?? "(无)\n"
        let safe = r.game.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Husk 崩溃报告 - \(safe).txt")
        do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { return nil }
        return url
    }
}

/// 游戏搞崩 Husk 后，启动时展示的弹窗。
struct CrashReportSheet: View {
    let report: CrashReport.Report
    @Environment(\.dismiss) private var dismiss
    @State private var file: URL?
    @State private var reporting: CompatSubject?

    /// 该游戏，用于向兼容性列表提交报告。
    private var subject: CompatSubject? {
        guard let app = TranslationLayerStore.shared.apps.first(where: { $0.id == report.appID }), let pkg = app.packageName else { return nil }
        return CompatSubject(package: pkg, name: app.label, isGame: LibraryItem.game(app).isGame, iconPath: app.iconPath,
                             crash: "\(report.cause.title)。\(report.cause.detail)")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 30)).foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(report.cause.title).font(.title3.weight(.semibold))
                            Text(report.game).foregroundStyle(.secondary)
                        }
                    }
                    Text(report.cause.detail).font(.callout)

                    if !report.excerpt.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("末尾日志").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                            Text(report.excerpt.joined(separator: "\n"))
                                .font(.system(size: 10.5, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    if let file {
                        ShareLink(item: file) {
                            Label("分享报告", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if let subject {
                        Button { reporting = subject } label: {
                            Label("上报到兼容性列表", systemImage: "list.bullet.clipboard")
                                .frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                    }
                    Text("报告包含本次运行的完整日志，以及所用设备和构建版本。除非你主动分享，否则不会发送到任何地方。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .navigationTitle("崩溃报告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .task { file = CrashReport.writeReport(report) }
        .sheet(item: $reporting) { CompatReportSheet(subject: $0) }
    }
}
