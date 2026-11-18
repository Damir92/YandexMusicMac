import Foundation
import CryptoKit
import IOKit

/// Thread-safe manager for secure, encrypted credentials storage on macOS.
///
/// Uses an AES-256-GCM authenticated encrypted vault stored in `~/Library/Application Support/YandexMusicMac/`
/// with strict owner-only POSIX permissions (`0600` file / `0700` directory), excluded from Time Machine backups,
/// and encrypted with a machine- & user-bound 256-bit key derived via `HKDF<SHA256>` from `IOPlatformUUID`.
///
/// This completely eliminates repetitive macOS Keychain password prompts caused by ad-hoc code signing
/// (`codesign --sign -`) changing CDHash across rebuilds and updates, while keeping credentials strongly
/// encrypted at rest and non-portable across machines.
public final class KeychainManager: @unchecked Sendable {
    public static let shared = KeychainManager()

    public static let defaultService = "com.yandexmusic.mac.credentials"

    private let service: String
    private let accessGroup: String?
    private let vaultURL: URL
    private let symmetricKey: SymmetricKey

    private let lock = NSLock()
    private var inMemoryCache: [String: String] = [:]
    private var hasLoadedFromDisk: Bool = false

    public enum KeychainKey: String, Sendable {
        case oauthToken = "ym_oauth_token"
        case userId = "ym_user_id"
    }

    public enum KeychainError: Error, LocalizedError, Sendable {
        case itemNotFound
        case duplicateItem
        case unexpectedStatus(OSStatus)
        case invalidDataConversion
        case encryptionFailed
        case storageFailure(String)

        public var errorDescription: String? {
            switch self {
            case .itemNotFound:
                return "Item not found in secure vault."
            case .duplicateItem:
                return "Duplicate item in secure vault."
            case .unexpectedStatus(let status):
                return "Secure storage error status: \(status)"
            case .invalidDataConversion:
                return "Data could not be converted to string."
            case .encryptionFailed:
                return "Failed to encrypt credentials payload."
            case .storageFailure(let message):
                return "Secure storage failure: \(message)"
            }
        }
    }

    public init(service: String = KeychainManager.defaultService, accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
        self.vaultURL = Self.makeVaultURL(for: service)
        self.symmetricKey = Self.deriveVaultKey(service: service, accessGroup: accessGroup)
    }

    // Internal accessor for unit tests to verify on-disk encryption & permissions
    var storageFileURL: URL { vaultURL }

    // MARK: - Generic Secure Storage Operations

    public func setString(_ value: String, for key: KeychainKey) throws {
        lock.lock()
        defer { lock.unlock() }

        ensureLoadedLocked()
        inMemoryCache[key.rawValue] = value
        try persistLocked()
    }

    public func getString(for key: KeychainKey) throws -> String? {
        lock.lock()
        defer { lock.unlock() }

        ensureLoadedLocked()
        return inMemoryCache[key.rawValue]
    }

    public func delete(for key: KeychainKey) throws {
        lock.lock()
        defer { lock.unlock() }

        ensureLoadedLocked()
        inMemoryCache.removeValue(forKey: key.rawValue)
        try persistLocked()
    }

    public func clearAll() throws {
        lock.lock()
        defer { lock.unlock() }

        inMemoryCache.removeAll()
        hasLoadedFromDisk = true
        try persistLocked()
    }

    // MARK: - Specialized Convenience API

    public func saveToken(_ token: String) throws {
        try setString(token.trimmingCharacters(in: .whitespacesAndNewlines), for: .oauthToken)
    }

    public func getToken() -> String? {
        try? getString(for: .oauthToken)
    }

    public func deleteToken() throws {
        try delete(for: .oauthToken)
    }

    public func saveUserId(_ userId: String) throws {
        try setString(userId.trimmingCharacters(in: .whitespacesAndNewlines), for: .userId)
    }

    public func getUserId() -> String? {
        try? getString(for: .userId)
    }

    public func deleteUserId() throws {
        try delete(for: .userId)
    }

    // MARK: - Encrypted Vault Persistence (AES-256-GCM + HKDF-SHA256)

    private func ensureLoadedLocked() {
        guard !hasLoadedFromDisk else { return }
        hasLoadedFromDisk = true

        guard FileManager.default.fileExists(atPath: vaultURL.path) else {
            return
        }

        do {
            let encryptedData = try Data(contentsOf: vaultURL)
            guard !encryptedData.isEmpty else { return }

            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            let decryptedData = try AES.GCM.open(sealedBox, using: symmetricKey)
            let decoded = try JSONDecoder().decode([String: String].self, from: decryptedData)
            inMemoryCache = decoded
        } catch {
            print("[KeychainManager] Failed to decrypt credential vault (resetting cache): \(error.localizedDescription)")
            inMemoryCache = [:]
        }
    }

    private func persistLocked() throws {
        let fm = FileManager.default

        if inMemoryCache.isEmpty {
            if fm.fileExists(atPath: vaultURL.path) {
                try fm.removeItem(at: vaultURL)
            }
            return
        }

        let parentDir = vaultURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: parentDir.path) {
            try fm.createDirectory(
                at: parentDir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
            )
        } else {
            try? fm.setAttributes([.posixPermissions: NSNumber(value: Int16(0o700))], ofItemAtPath: parentDir.path)
        }

        let plaintext = try JSONEncoder().encode(inMemoryCache)
        let sealedBox = try AES.GCM.seal(plaintext, using: symmetricKey)
        guard let combined = sealedBox.combined else {
            throw KeychainError.encryptionFailed
        }

        do {
            try combined.write(to: vaultURL, options: .atomic)
            try fm.setAttributes([.posixPermissions: NSNumber(value: Int16(0o600))], ofItemAtPath: vaultURL.path)

            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableURL = vaultURL
            try? mutableURL.setResourceValues(resourceValues)
        } catch {
            throw KeychainError.storageFailure(error.localizedDescription)
        }
    }

    private static func makeVaultURL(for service: String) -> URL {
        let fm = FileManager.default
        if service == defaultService {
            let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
            return appSupport
                .appendingPathComponent("YandexMusicMac", isDirectory: true)
                .appendingPathComponent("credentials.vault", isDirectory: false)
        } else {
            let hash = SHA256.hash(data: Data(service.utf8))
                .prefix(12)
                .map { String(format: "%02x", $0) }
                .joined()
            return fm.temporaryDirectory
                .appendingPathComponent("YandexMusicMacVaults", isDirectory: true)
                .appendingPathComponent("vault_\(hash).enc", isDirectory: false)
        }
    }

    private static func deriveVaultKey(service: String, accessGroup: String?) -> SymmetricKey {
        let machineUUID = hardwarePlatformUUID()
        let uid = getuid()
        let home = NSHomeDirectory()
        let materialString = "\(machineUUID)|uid:\(uid)|home:\(home)|group:\(accessGroup ?? "")"
        let inputKey = SymmetricKey(data: Data(materialString.utf8))
        let salt = Data("com.yandexmusic.mac.vault.v1|\(service)".utf8)
        let info = Data("AES-256-GCM-Credentials-Vault".utf8)

        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: salt,
            info: info,
            outputByteCount: 32
        )
    }

    private static func hardwarePlatformUUID() -> String {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard platformExpert != 0 else { return "fallback-mac-host" }
        defer { IOObjectRelease(platformExpert) }

        if let cfValue = IORegistryEntryCreateCFProperty(
            platformExpert,
            "IOPlatformUUID" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String, !cfValue.isEmpty {
            return cfValue
        }
        return "fallback-mac-host"
    }
}
