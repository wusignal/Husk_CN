// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UIKit

/// Husk 的兼容性列表（antiweb.lol）：每个应用在所有人设备上的运行情况，旁边是它在这台 iPhone 上的运行情况（GameStatus）。
///
/// 列表不时抓取一次并存盘，因此离线也能看，启动时零成本。报告发到同一站点：游戏跑得怎样，
/// 由 Husk 自动填好设备、iOS 版本、构建号和 JIT 方式后发出。
@MainActor
final class CompatibilityStore: ObservableObject {
    static let shared = CompatibilityStore()

    /// 主站，以及它 Render 上的备用地址，用于主站无响应时。测试时可在最前面放一个自定义地址
    /// (defaults write com.husk.app husk.compatURL http://…).
    static var sites: [URL] {
        let custom = UserDefaults.standard.string(forKey: "husk.compatURL").flatMap(URL.init(string:))
        return [custom, URL(string: "https://antiweb.lol"), URL(string: "https://antiweb-website.onrender.com")].compactMap { $0 }
    }
    /// 上次响应的那个，用于链接。
    static var site: URL { shared.workingSite ?? sites[0] }
    @Published private(set) var workingSite: URL?

    /// 依次请求每个站点，直到有一个返回状态码低于 500（4xx 是站点的回答，不是故障）。
    private func call(_ path: String, _ prepare: (inout URLRequest) -> Void = { _ in }) async throws -> (Data, HTTPURLResponse) {
        var last: Error = URLError(.cannotConnectToHost)
        for site in Self.sites {
            var request = URLRequest(url: site.appendingPathComponent(path))
            request.timeoutInterval = 15
            prepare(&request)
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode < 500 else { throw URLError(.badServerResponse) }
                if workingSite != site { workingSite = site; HuskLog.log("compat", "using \(site.host ?? site.absoluteString)") }
                return (data, http)
            } catch {
                HuskLog.log("compat", "\(site.host ?? "?") did not answer: \(error.localizedDescription)")
                last = error
            }
        }
        throw last
    }
    /// Husk 是否在玩过游戏后询问运行情况（设置项）。
    static let askKey = "husk.compatAsk"

    enum Status: String, Codable {
        case works, opens, broken, protected
        var label: String {
            switch self {
            case .works: return "可玩"
            case .opens: return "能打开"
            case .broken: return "无法运行"
            case .protected: return "受保护"
            }
        }
        var symbol: String {
            switch self {
            case .works: return "checkmark.circle.fill"
            case .opens: return "circle.lefthalf.filled"
            case .broken: return "xmark.circle.fill"
            case .protected: return "lock.fill"
            }
        }
        var color: Color {
            switch self {
            case .works: return .green
            case .opens: return .orange
            case .broken: return .red
            case .protected: return .secondary
            }
        }
        var explanation: String {
            switch self {
            case .works: return "可运行，游戏或应用功能正常。"
            case .opens: return "能启动并显示界面，但未经完整测试或存在问题。"
            case .broken: return "启动时崩溃或直接关闭。"
            case .protected: return "拒绝在真实 Android 手机之外运行（反作弊、防篡改或 DRM）。Husk 无法绕过。"
            }
        }
    }

    struct Entry: Codable {
        let package: String
        let name: String
        let icon: String?
        let official: Official?
        let community: Community
        struct Official: Codable { let status: Status; let note: String }
        struct Community: Codable { let reports: Int; let counts: [String: Int] }

        /// 有官方结果时用官方，否则用多数人上报的结果。
        var status: Status? {
            if let official { return official.status }
            return community.counts.filter { $0.value > 0 }.max { $0.value < $1.value }.flatMap { Status(rawValue: $0.key) }
        }
    }

    @Published private(set) var entries: [String: Entry] = [:]
    @Published private(set) var updated: Date?
    private var fetching = false

    private static var cacheFile: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("compatibility.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.cacheFile), let list = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = Dictionary(list.map { ($0.package, $0) }, uniquingKeysWith: { a, _ in a })
            updated = (try? FileManager.default.attributesOfItem(atPath: Self.cacheFile.path)[.modificationDate]) as? Date
        }
    }

    func entry(_ package: String?) -> Entry? { package.flatMap { entries[$0] } }

    /// 磁盘上的副本超过几小时就重新拉取（或强制刷新）。
    func refresh(force: Bool = false) async {
        guard !fetching, force || updated.map({ Date().timeIntervalSince($0) > 6 * 3600 }) ?? true else { return }
        fetching = true
        defer { fetching = false }
        struct Response: Decodable { let apps: [Entry] }
        do {
            let (data, response) = try await call("api/apps")
            guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
            let list = try JSONDecoder().decode(Response.self, from: data).apps
            entries = Dictionary(list.map { ($0.package, $0) }, uniquingKeysWith: { a, _ in a })
            updated = Date()
            try? JSONEncoder().encode(list).write(to: Self.cacheFile, options: .atomic)
            HuskLog.log("compat", "list updated: \(list.count) apps")
        } catch {
            HuskLog.log("compat", "list not updated: \(error.localizedDescription)")
        }
    }

    // MARK: 上报

    /// Husk 在每条报告中自动填写的信息。
    static var device: String {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return machine.isEmpty ? UIDevice.current.model : machine
    }
    static var jitMethod: String {
        switch JITCoordinator.shared.resolvedMethod {
        case .builtIn: return "StikJIT (内置)"
        case .stikDebug: return "StikDebug"
        case .trollStore: return "TrollStore"
        case .jailbreak: return "越狱"
        case .automatic: return "其他"
        }
    }
    static var build: String { (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "" }

    /// 应用启动器图标的小 PNG，用于列表中尚无图标的首次上报。
    static func iconPNG(_ path: String?) -> String? {
        guard let path, let image = UIImage(contentsOfFile: path) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 128, height: 128)
        let png = UIGraphicsImageRenderer(size: size, format: format).pngData { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return png.count <= 60_000 ? png.base64EncodedString() : nil
    }

    func send(package: String, name: String, isGame: Bool, status: Status, notes: String, author: String, iconPath: String? = nil) async throws {
        var body: [String: String] = [
            "package": package, "name": name, "type": isGame ? "game" : "app", "status": status.rawValue,
            "device": Self.device, "ios": UIDevice.current.systemVersion, "build": Self.build, "jit": Self.jitMethod,
            "notes": notes, "author": author,
        ]
        if body["author"]?.isEmpty == true { body["author"] = nil }
        if entry(package)?.icon == nil, let icon = Self.iconPNG(iconPath) { body["icon"] = icon }
        let payload = try JSONSerialization.data(withJSONObject: body)
        let (data, http) = try await call("api/reports") {
            $0.httpMethod = "POST"
            $0.setValue("application/json", forHTTPHeaderField: "Content-Type")
            $0.httpBody = payload
            $0.timeoutInterval = 20
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw NSError(domain: "Compatibility", code: 1, userInfo: [NSLocalizedDescriptionKey: message ?? "无法连接到兼容性列表。"])
        }
        HuskLog.log("compat", "reported \(package): \(status.rawValue)")
        markAsked(package)
        await refresh(force: true)
    }

    // 每个游戏每个 Husk 构建询问一次：新构建可能改变游戏运行情况。
    private func askedKey(_ package: String) -> String { "husk.compatAsked.\(package)" }
    func shouldAsk(_ package: String?) -> Bool {
        guard let package, UserDefaults.standard.object(forKey: Self.askKey) as? Bool ?? true else { return false }
        return UserDefaults.standard.string(forKey: askedKey(package)) != Self.build
    }
    func markAsked(_ package: String) { UserDefaults.standard.set(Self.build, forKey: askedKey(package)) }

    func pageURL(_ package: String) -> URL { (workingSite ?? Self.sites[0]).appendingPathComponent("app").appendingPathComponent(package) }
}

/// 报告的对象，用于弹窗。
struct CompatSubject: Identifiable {
    let package: String
    let name: String
    let isGame: Bool
    /// Husk 为它显示的图标，列表中无图标时一并发送。
    var iconPath: String? = nil
    /// 崩溃时填入：它没跑起来，以及原因。
    var crash: String? = nil
    /// 玩过之后询问，而非来自页面按钮。
    var afterPlaying = false
    var id: String { package }
}

/// 游戏页面的分组：它在所有人设备上跑得怎样，以及在此处上报你这边的运行情况。
struct CompatibilitySection: View {
    let subject: CompatSubject
    @Binding var reporting: CompatSubject?
    @ObservedObject private var compat = CompatibilityStore.shared

    var body: some View {
        let entry = compat.entry(subject.package)
        Section {
            if let entry, let status = entry.status {
                HStack(spacing: 12) {
                    Image(systemName: status.symbol).font(.title3).foregroundStyle(status.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(status.label).font(.body.weight(.semibold))
                        Text(entry.official?.note.isEmpty == false ? entry.official!.note : status.explanation)
                            .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)
                if entry.community.reports > 0 {
                    LabeledContent("玩家报告", value: "\(entry.community.reports)")
                }
            } else {
                Text("尚未在列表中。来做第一个说明它运行情况的人吧。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button { reporting = subject } label: { Label("上报运行情况", systemImage: "square.and.pencil") }
            Link(destination: compat.pageURL(subject.package)) { Label("在 antiweb.lol 上打开", systemImage: "safari") }
        } header: {
            Text("兼容性")
        } footer: {
            if entry?.official != nil { Text("由 Husk 团队在 iPhone 上实测。") }
        }
    }
}

/// 上报弹窗：可玩、能打开或无法运行，再加一段说明。其他信息自动填好。
struct CompatReportSheet: View {
    let subject: CompatSubject
    @Environment(\.dismiss) private var dismiss
    @AppStorage("husk.compatAuthor") private var author = ""
    @State private var status: CompatibilityStore.Status?
    @State private var notes = ""
    @State private var sending = false
    @State private var error: String?
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach([CompatibilityStore.Status.works, .opens, .broken], id: \.self) { s in
                        Button { status = s } label: {
                            HStack {
                                Label(s == .opens ? "能打开，但有问题" : s.label, systemImage: s.symbol)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if status == s { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                    }
                } header: {
                    Text(subject.afterPlaying ? "\(subject.name) 跑得怎样？" : "\(subject.name) 跑得怎样？")
                }
                Section("备注") {
                    TextField("哪里正常、哪里不行、你玩到了哪一步", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    TextField("匿名", text: $author)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("你的昵称")
                } footer: {
                    Text("随报告发送：\(CompatibilityStore.device)，iOS \(UIDevice.current.systemVersion)，Husk 构建 \(CompatibilityStore.build)，JIT 方式：\(CompatibilityStore.jitMethod)。这些信息会公开显示在 antiweb.lol 上。")
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(sent ? "谢谢！" : "上报")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(subject.afterPlaying ? "暂不" : "取消") {
                        if subject.afterPlaying { CompatibilityStore.shared.markAsked(subject.package) }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if sending { ProgressView() } else {
                        Button("发送") { send() }.disabled(status == nil)
                    }
                }
            }
        }
        .onAppear {
            if let crash = subject.crash {
                status = .broken
                if notes.isEmpty { notes = crash }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func send() {
        guard let status else { return }
        sending = true
        error = nil
        Task {
            do {
                try await CompatibilityStore.shared.send(package: subject.package, name: subject.name, isGame: subject.isGame,
                                                         status: status, notes: notes, author: author, iconPath: subject.iconPath)
                sent = true
                try? await Task.sleep(nanoseconds: 600_000_000)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            sending = false
        }
    }
}

/// 列表中的小标签：应用在兼容性列表上的状态。
struct CompatBadge: View {
    let status: CompatibilityStore.Status
    var body: some View {
        Label(status.label, systemImage: status.symbol)
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.medium))
            .foregroundStyle(status.color)
    }
}
