// SPDX-License-Identifier: GPL-2.0-or-later
import Combine
import Foundation

/// Where the image's files are published, and the defaults the download uses.
///
/// GitHub's own directory is what the JIT helper fetches from; the field under
/// the buttons replaces it when a mirror is quicker to reach, which is often the
/// case on a network that throttles GitHub.
enum DeveloperImageAddress {
    static let fallback =
        "https://github.com/doronz88/DeveloperDiskImage/raw/refs/heads/main/PersonalizedImages/Xcode_iOS_DDI_Cryptex/"
    /// UserDefaults key the field is kept under.
    static let key = "husk.ddiSource"

    static var url: URL {
        let stored = UserDefaults.standard.string(forKey: key) ?? ""
        let text = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = text.isEmpty ? fallback : text
        // A trailing slash matters: these are files under a directory, not
        // siblings that replace its last component.
        let withSlash = base.hasSuffix("/") ? base : base + "/"
        return URL(string: withSlash) ?? URL(string: fallback)!
    }
}

/// Gets Apple's Developer Disk Image onto the device without leaving the setup
/// screen waiting on a download it cannot show.
///
/// The image is normally fetched by Husk's JIT helper as part of the setup check,
/// from a GitHub directory that is slow or blocked on some networks. When that
/// stalls, the check sits on "Checking LocalDevVPN and the Developer Disk Image…"
/// with nothing to say, and there is no way to hand the files over. This fetches
/// the same five files here -- where there is a progress bar, a cancel button and
/// a retry -- or takes them from Files, and passes them to the helper to store.
@MainActor
final class DeveloperImageLoader: ObservableObject {

    /// What the card under the steps is doing.
    enum Phase: Equatable {
        case idle
        /// A line of text with no measurable progress, such as reading files.
        case working(String)
        /// A line of text and how far along it is, 0 to 1.
        case progress(String, Double)
        case done(String)
        case failed(String)
    }

    /// The files the image is made of. Three are required; iOS 17.4 and later
    /// also mount it as a cryptex, which the other two describe.
    enum Component: String, CaseIterable {
        case image = "Image.dmg"
        case trustcache = "Image.dmg.trustcache"
        case manifest = "BuildManifest.plist"
        case cryptexInfo = "Image.dmg.cryptex_info"
        case rootHash = "Image.dmg.root_hash"

        var isRequired: Bool {
            switch self {
            case .image, .trustcache, .manifest: return true
            case .cryptexInfo, .rootHash: return false
            }
        }
    }

    enum Failure: LocalizedError {
        case status(Int)
        case incomplete
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .status(let code):
                return L("The download stopped with HTTP %lld. Try again, or paste a mirror address.",
                         code)
            case .incomplete:
                return L("Those files are not a whole Developer Disk Image. Image.dmg, "
                       + "Image.dmg.trustcache and BuildManifest.plist are all needed.")
            case .unreadable(let name):
                return L("“%@” could not be read.", name)
            }
        }
    }

    @Published private(set) var phase: Phase = .idle

    /// A download or an import is under way.
    var busy: Bool {
        switch phase {
        case .idle, .done, .failed: return false
        case .working, .progress: return true
        }
    }

    private var task: Task<Void, Never>?

    private static var source: URL { DeveloperImageAddress.url }

    // MARK: Downloading

    func download() {
        guard task == nil else { return }
        let base = Self.source
        HuskLog.log("jit", "developer image: downloading from \(base.absoluteString)")
        phase = .progress(L("Starting the download…"), 0)
        task = Task { [weak self] in
            await self?.run(base: base)
            self?.task = nil
        }
    }

    private func run(base: URL) async {
        var files = HuskJITRequest.DDIFiles()
        let count = Double(Component.allCases.count)
        do {
            for (index, component) in Component.allCases.enumerated() {
                try Task.checkCancellation()
                phase = .progress(L("Downloading %@ (%lld of %lld)…", component.rawValue,
                                    index + 1, Component.allCases.count),
                                  Double(index) / count)
                let data = try await fetch(component.rawValue, from: base)
                if let data {
                    switch component {
                    case .image: files.image = data
                    case .trustcache: files.trustcache = data
                    case .manifest: files.manifest = data
                    case .cryptexInfo: files.cryptexInfo = data
                    case .rootHash: files.rootHash = data
                    }
                } else if component.isRequired {
                    throw Failure.status(404)
                }
            }
            guard files.isComplete else { throw Failure.incomplete }
            try await send(files)
        } catch is CancellationError {
            HuskLog.log("jit", "developer image: download cancelled")
            phase = .idle
        } catch {
            HuskLog.log("jit", "developer image: download failed, \(error.localizedDescription)")
            phase = .failed(error.localizedDescription)
        }
    }

    /// One file, or nil when the server does not have it: the two cryptex files
    /// are only published for the versions that mount the image as a cryptex.
    private func fetch(_ name: String, from base: URL) async throws -> Data? {
        guard let url = URL(string: name, relativeTo: base) else {
            throw Failure.unreadable(name)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (temporary, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.status(0) }
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw Failure.status(http.statusCode) }
        return try Data(contentsOf: temporary)
    }

    // MARK: Importing

    func use(_ urls: [URL]) {
        guard task == nil else { return }
        phase = .working(L("Reading the files…"))
        task = Task { [weak self] in
            await self?.read(urls)
            self?.task = nil
        }
    }

    private func read(_ urls: [URL]) async {
        var found: [String: Data] = [:]
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            collect(url, into: &found, depth: 0)
        }
        let names = Component.allCases.map(\.rawValue)
        HuskLog.log("jit", "developer image: imported \(found.keys.filter { names.contains($0) }.sorted())")
        do {
            var files = HuskJITRequest.DDIFiles()
            files.image = found[Component.image.rawValue]
            files.trustcache = found[Component.trustcache.rawValue]
            files.manifest = found[Component.manifest.rawValue]
            files.cryptexInfo = found[Component.cryptexInfo.rawValue]
            files.rootHash = found[Component.rootHash.rawValue]
            guard files.isComplete else { throw Failure.incomplete }
            try await send(files)
        } catch {
            HuskLog.log("jit", "developer image: import failed, \(error.localizedDescription)")
            phase = .failed(error.localizedDescription)
        }
    }

    /// A picked folder may be the image's own directory or the folder above it,
    /// so the search goes a few levels down rather than only looking at its top.
    private func collect(_ url: URL, into found: inout [String: Data], depth: Int) {
        guard depth < 3 else { return }
        let manager = FileManager.default
        var isFolder: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isFolder) else { return }
        if isFolder.boolValue {
            let children = (try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil,
                                                             options: [.skipsHiddenFiles])) ?? []
            for child in children { collect(child, into: &found, depth: depth + 1) }
            return
        }
        let name = url.lastPathComponent
        guard Component.allCases.contains(where: { $0.rawValue == name }) else { return }
        if let data = try? Data(contentsOf: url) { found[name] = data }
    }

    // MARK: Handing over

    private func send(_ files: HuskJITRequest.DDIFiles) async throws {
        phase = .working(L("Handing the image to Husk's JIT helper…"))
        let message = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<String, Error>) in
            JITCoordinator.shared.installDeveloperImage(files) { result in
                continuation.resume(with: result)
            }
        }
        phase = .done(message)
        // The files are where the setup check looks now, so mounting them is the
        // next thing to do, and it is what the person was trying to reach.
        JITCoordinator.shared.prepareBuiltIn()
    }

    func cancel() {
        task?.cancel()
        task = nil
        phase = .idle
    }

    func reset() {
        task?.cancel()
        task = nil
        phase = .idle
    }
}
