// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UIKit

/// Husk 自行记录的游戏上次运行结果：可玩、崩溃或无法启动。
///
/// 发生时写入游戏目录下的 status.json，这样资源库就能一眼看出哪些游戏在这台 iPhone 上能跑，无需人工维护列表。
@MainActor
final class GameStatusStore: ObservableObject {
    static let shared = GameStatusStore()

    enum Result: String, Codable {
        case plays, crashed, failed

        var label: String {
            switch self {
            case .plays: return "可玩"
            case .crashed: return "上次崩溃"
            case .failed: return "无法启动"
            }
        }
        var symbol: String {
            switch self {
            case .plays: return "checkmark.circle.fill"
            case .crashed: return "exclamationmark.triangle.fill"
            case .failed: return "xmark.circle.fill"
            }
        }
        var color: Color {
            switch self {
            case .plays: return .green
            case .crashed: return .orange
            case .failed: return .red
            }
        }
    }

    struct Status: Codable {
        var result: Result
        var time: Date
        var detail: String?
        /// 停止原因（来自运行日志，由 AppDiagnosis 给出）
        var why: Why?
    }
    struct Why: Codable { var kind: String; var title: String; var detail: String; var evidence: String? }

    /// 上次运行停止的原因（在它重新可玩之前）。
    func diagnosis(_ appID: String) -> AppDiagnosis? {
        guard let s = status(appID), s.result != .plays, let w = s.why, let kind = AppDiagnosis.Kind(rawValue: w.kind) else { return nil }
        return AppDiagnosis(kind: kind, title: w.title, detail: w.detail, evidence: w.evidence)
    }

    func record(_ appID: String, _ result: Result, diagnosis d: AppDiagnosis) {
        guard !appID.isEmpty else { return }
        let s = Status(result: result, time: Date(), detail: d.title, why: Why(kind: d.kind.rawValue, title: d.title, detail: d.detail, evidence: d.evidence))
        cache[appID] = s
        if let data = try? JSONEncoder().encode(s) { try? data.write(to: Self.file(appID), options: .atomic) }
        HuskLog.log("status", "\(appID): \(result.rawValue) (\(d.title))")
    }

    @Published private var cache: [String: Status] = [:]
    private var loaded: Set<String> = []

    private static func file(_ appID: String) -> URL {
        TranslationLayer.root.appendingPathComponent(appID, isDirectory: true).appendingPathComponent("status.json")
    }

    func status(_ appID: String) -> Status? {
        if !loaded.contains(appID) {
            loaded.insert(appID)
            if let data = try? Data(contentsOf: Self.file(appID)),
               let s = try? JSONDecoder().decode(Status.self, from: data) { cache[appID] = s }
        }
        return cache[appID]
    }

    func record(_ appID: String, _ result: Result, detail: String? = nil) {
        guard !appID.isEmpty, status(appID)?.result != result || result != .plays else { return }
        let s = Status(result: result, time: Date(), detail: detail, why: nil)
        cache[appID] = s
        if let data = try? JSONEncoder().encode(s) { try? data.write(to: Self.file(appID), options: .atomic) }
        HuskLog.log("status", "\(appID): \(result.rawValue)\(detail.map { " (\($0))" } ?? "")")
    }
}

/// 资源库中游戏图标上的小标记。
struct GameStatusBadge: View {
    let result: GameStatusStore.Result

    var body: some View {
        Image(systemName: result.symbol)
            .font(.system(size: 15, weight: .bold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, result.color)
            .background(Circle().fill(Color(uiColor: .systemBackground)).padding(1))
            .accessibilityLabel(result.label)
    }
}
