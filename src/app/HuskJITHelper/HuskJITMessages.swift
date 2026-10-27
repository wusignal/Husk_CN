// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// Codable messages shared by Husk and its JIT helper extension. Compiled into
/// both targets. Each travels as JSON in an extension request's item
/// (userInfo[itemKey]), to the helper and back.
struct HuskJITRequest: Codable, Sendable {
    static let itemKey = "husk-jit-request"

    enum Operation: String, Codable, Sendable {
        /// Check LocalDevVPN and download, mount and verify the Developer Disk Image.
        case prepare
        /// Attach to `targetPID` and run the JIT script until it detaches.
        case enable
        case resetDDI
        /// Put a Developer Disk Image the app fetched or imported into the cache
        /// `prepare` looks in, so it is mounted instead of downloaded.
        case installDDI
    }

    /// The files Apple's Developer Disk Image is made of, as bytes rather than
    /// as paths: the helper and the app are separate processes with separate
    /// containers, and an extension request is the only thing that crosses.
    ///
    /// A device on iOS 17.4 and later takes the cryptex set (all five); the
    /// older personalized set is the image, its trust cache and the manifest.
    struct DDIFiles: Codable, Sendable {
        var image: Data? = nil
        var trustcache: Data? = nil
        var manifest: Data? = nil
        var cryptexInfo: Data? = nil
        var rootHash: Data? = nil

        /// Whether there is enough here to mount: the image, its trust cache and
        /// the manifest it is personalized against.
        var isComplete: Bool { image != nil && trustcache != nil && manifest != nil }

        var names: [String] {
            [image.map { _ in "Image.dmg" },
             trustcache.map { _ in "Image.dmg.trustcache" },
             manifest.map { _ in "BuildManifest.plist" },
             cryptexInfo.map { _ in "Image.dmg.cryptex_info" },
             rootHash.map { _ in "Image.dmg.root_hash" }].compactMap { $0 }
        }
    }

    let operation: Operation
    let targetPID: Int32?
    let pairingData: Data?
    let scriptBase64: String?
    /// The port the device is currently advertising for RemotePairing. iOS picks
    /// a new one when it boots; nil means StikJIT's default.
    let rsdPort: UInt16?
    /// A Developer Disk Image to store before mounting; nil for every request
    /// that is not `installDDI`.
    let ddi: DDIFiles?

    static func prepare(pairingData: Data, rsdPort: UInt16? = nil) -> HuskJITRequest {
        HuskJITRequest(operation: .prepare, targetPID: nil,
                       pairingData: pairingData, scriptBase64: nil, rsdPort: rsdPort, ddi: nil)
    }

    static func enable(targetPID: Int32, pairingData: Data,
                       scriptBase64: String, rsdPort: UInt16? = nil) -> HuskJITRequest {
        HuskJITRequest(operation: .enable, targetPID: targetPID,
                       pairingData: pairingData, scriptBase64: scriptBase64, rsdPort: rsdPort, ddi: nil)
    }

    static var resetDDI: HuskJITRequest {
        HuskJITRequest(operation: .resetDDI, targetPID: nil,
                       pairingData: nil, scriptBase64: nil, rsdPort: nil, ddi: nil)
    }

    static func installDDI(_ files: DDIFiles) -> HuskJITRequest {
        HuskJITRequest(operation: .installDDI, targetPID: nil,
                       pairingData: nil, scriptBase64: nil, rsdPort: nil, ddi: files)
    }

    struct Response: Codable, Sendable {
        static let itemKey = "husk-jit-response"
        let success: Bool
        let message: String
        let txmPresent: Bool?
    }
}
