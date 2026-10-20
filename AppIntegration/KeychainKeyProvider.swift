// KeychainKeyProvider.swift — WezWordn AppIntegration (iOS only)
//
// Production `KeyProvider` for LocalEncryptedStorage, backed by the iOS
// Keychain (Security framework). The 32-byte file-encryption key is
// generated once with SecRandomCopyBytes, stored as a generic password
// item, and never logged, exported, or synchronised to iCloud Keychain.
//
// Accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly — the key is
// available only while the device is unlocked, never migrates to a new
// device via backup/restore, and is wiped with the app's keychain items on
// uninstall. Consequence (documented, not hidden): encrypted files in the
// app container cannot be decrypted after a device migration that restores
// files without keychain items; users must export decrypted copies first
// (see SECURITY.md).
//
// Type note: `KeyProvider.encryptionKey()` returns swift-crypto's
// `SymmetricKey` (module `Crypto`), because that is the type
// LocalEncryptedStorage is written against. On iOS the app target must
// link the same swift-crypto `Crypto` product as WezWordnCore — see
// AppIntegration/README.md for the XcodeGen snippet.

#if os(iOS)

import Crypto
import Foundation
import LocalEncryptedStorage
import Security

public enum KeychainKeyProviderError: Error {
    case randomGenerationFailed(OSStatus)
    case keychain(OSStatus)
    case unexpectedKeySize(Int)
}

public struct KeychainKeyProvider: KeyProvider {
    public let service: String
    public let account: String

    public init(
        service: String = "com.wezcrypt.wezwordn.local-files",
        account: String = "file-encryption-key-v1"
    ) {
        self.service = service
        self.account = account
    }

    public func encryptionKey() throws -> SymmetricKey {
        if let existing = try loadKeyData() {
            guard existing.count == 32 else {
                throw KeychainKeyProviderError.unexpectedKeySize(existing.count)
            }
            return SymmetricKey(data: existing)
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw KeychainKeyProviderError.randomGenerationFailed(status)
        }
        let keyData = Data(bytes)
        try storeKeyData(keyData)
        return SymmetricKey(data: keyData)
    }

    // MARK: - Keychain primitives

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func loadKeyData() throws -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainKeyProviderError.keychain(status)
        }
    }

    private func storeKeyData(_ data: Data) throws {
        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        query[kSecAttrSynchronizable as String] = false
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw KeychainKeyProviderError.keychain(status)
        }
    }

    /// Deletes the stored key. After this call every file encrypted with it
    /// becomes permanently undecryptable — callers must confirm with the
    /// user and offer decrypted export first.
    public func deleteKey() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainKeyProviderError.keychain(status)
        }
    }
}

#endif
