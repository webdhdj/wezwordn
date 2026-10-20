import Foundation
import Crypto
import LocalEncryptedStorage

// MARK: - Encrypted backup format (documented)
//
// A backup is a single JSON file holding ONE AES-256-GCM sealed payload:
//
//   BackupPackage (outer, plaintext JSON — metadata only, no secrets):
//     format          "WEZBACKUP"
//     version         1
//     kdfSalt         base64, 16 random bytes, fresh per export
//     kdfIterations   PBKDF2-HMAC-SHA256 iteration count actually used
//     sealedPayload   base64 of AES.GCM.SealedBox.combined
//                     (nonce ‖ ciphertext ‖ tag) under the key
//                     PBKDF2(password UTF-8, kdfSalt, kdfIterations, 32)
//
//   BackupPayload (the decrypted plaintext, itself JSON):
//     manifest        BackupManifest — counts + SHA-256 fingerprints
//     store           the full SidecarStore (emails / TOTPs / file refs)
//     fileBlobs       [fileId: base64 of the .wzen file bytes AS STORED]
//                     Blobs stay encrypted under the vault storage key;
//                     the backup password only wraps the package. After a
//                     restore, files decrypt with the vault's current
//                     storage key (see LocalDataVault docs).
//
// Import safety: the package is decrypted and EVERY manifest fingerprint
// and count is verified before a single byte of current vault state is
// touched. A wrong password fails at the GCM open step
// (`backupBadPasswordOrCorrupt`) and the live vault is provably unchanged.

struct BackupPackage: Codable {
    var format: String
    var version: Int
    var kdfSalt: Data
    var kdfIterations: Int
    var sealedPayload: Data
}

struct BackupManifest: Codable, Equatable {
    var formatVersion: Int
    var schemaVersion: Int
    var createdAt: Date
    var emailCount: Int
    var totpCount: Int
    var fileCount: Int
    /// SHA-256 (hex) of the canonical (sorted-keys) JSON encoding of `store`.
    var storeSHA256: String
    /// fileId -> SHA-256 (hex) of the stored .wzen blob bytes.
    var fileFingerprints: [String: String]
}

struct BackupPayload: Codable {
    var manifest: BackupManifest
    var store: SidecarStore
    var fileBlobs: [String: Data]
}

extension LocalDataVault {
    public static let backupFormat = "WEZBACKUP"
    public static let backupFormatVersion = 1
    public static let defaultBackupIterations = 210_000

    private static func canonicalStoreData(_ store: SidecarStore) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(store)
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Exports the ENTIRE vault — all accounts' sidecar records plus every
    /// referenced encrypted file blob — as one password-encrypted package.
    public func exportBackup(password: String, iterations: Int = LocalDataVault.defaultBackupIterations,
                             to destination: URL) throws {
        precondition(iterations >= 1, "PBKDF2 iterations must be >= 1")
        let (store, blobs) = try withLock { () -> (SidecarStore, [String: Data]) in
            let store = snapshotLocked()
            var blobs: [String: Data] = [:]
            let fm = FileManager.default
            for entry in store.files {
                let url = filesDirectory.appendingPathComponent("\(entry.ref.fileId).wzen")
                guard fm.fileExists(atPath: url.path) else {
                    throw LocalDataVaultError.fileNotFound(entry.ref.fileId)
                }
                do { blobs[entry.ref.fileId] = try Data(contentsOf: url) } catch {
                    throw LocalDataVaultError.ioError("cannot read file blob \(entry.ref.fileId): \(error)")
                }
            }
            return (store, blobs)
        }

        let storeData = try Self.canonicalStoreData(store)
        var fingerprints: [String: String] = [:]
        for (fileId, blob) in blobs { fingerprints[fileId] = Self.sha256Hex(blob) }
        let manifest = BackupManifest(
            formatVersion: Self.backupFormatVersion,
            schemaVersion: store.schemaVersion,
            createdAt: Date(),
            emailCount: store.emails.count,
            totpCount: store.totps.count,
            fileCount: store.files.count,
            storeSHA256: Self.sha256Hex(storeData),
            fileFingerprints: fingerprints)

        let payload = BackupPayload(manifest: manifest, store: store, fileBlobs: blobs)
        let payloadEncoder = JSONEncoder()
        payloadEncoder.outputFormatting = [.sortedKeys]
        payloadEncoder.dateEncodingStrategy = .iso8601
        let payloadData = try payloadEncoder.encode(payload)

        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let key = SymmetricKey(data: PBKDF2.deriveKeySHA256(password: password, salt: salt,
                                                           iterations: iterations, keyLength: 32))
        let sealed = try AES.GCM.seal(payloadData, using: key)
        guard let combined = sealed.combined else {
            throw LocalDataVaultError.ioError("AES-GCM combined representation unavailable")
        }
        let package = BackupPackage(format: Self.backupFormat, version: Self.backupFormatVersion,
                                    kdfSalt: salt, kdfIterations: iterations,
                                    sealedPayload: Data(combined))
        let packageEncoder = JSONEncoder()
        packageEncoder.outputFormatting = [.sortedKeys]
        do {
            try packageEncoder.encode(package).write(to: destination, options: [.atomic])
        } catch {
            throw LocalDataVaultError.ioError("cannot write backup: \(error)")
        }
    }

    /// Restores a package produced by `exportBackup`.
    ///
    /// Verification order (all BEFORE any mutation of current state):
    /// package format -> PBKDF2 + AES-GCM open (wrong password throws
    /// `backupBadPasswordOrCorrupt`) -> manifest counts match the payload ->
    /// store fingerprint matches -> every blob fingerprint matches ->
    /// every file reference has a blob and vice versa -> schema is
    /// migratable. Only then are blobs written and records replaced.
    public func importBackup(password: String, from source: URL) throws {
        let packageData: Data
        do { packageData = try Data(contentsOf: source) } catch {
            throw LocalDataVaultError.ioError("cannot read backup: \(error)")
        }
        let package: BackupPackage
        do { package = try JSONDecoder().decode(BackupPackage.self, from: packageData) } catch {
            throw LocalDataVaultError.backupFormatInvalid("package is not a WEZBACKUP JSON document")
        }
        guard package.format == Self.backupFormat, package.version == Self.backupFormatVersion else {
            throw LocalDataVaultError.backupFormatInvalid("format/version mismatch")
        }
        guard package.kdfIterations >= 1 else {
            throw LocalDataVaultError.backupFormatInvalid("invalid kdfIterations")
        }
        let key = SymmetricKey(data: PBKDF2.deriveKeySHA256(password: password, salt: package.kdfSalt,
                                                           iterations: package.kdfIterations, keyLength: 32))
        let payloadData: Data
        do {
            let box = try AES.GCM.SealedBox(combined: package.sealedPayload)
            payloadData = try AES.GCM.open(box, using: key)
        } catch {
            // Wrong password OR any tampering: one error, no information leak.
            throw LocalDataVaultError.backupBadPasswordOrCorrupt
        }
        let payloadDecoder = JSONDecoder()
        payloadDecoder.dateDecodingStrategy = .iso8601
        let payload: BackupPayload
        do { payload = try payloadDecoder.decode(BackupPayload.self, from: payloadData) } catch {
            throw LocalDataVaultError.backupFormatInvalid("payload undecodable")
        }

        // ---- Full verification, still zero mutation ----
        let manifest = payload.manifest
        guard manifest.formatVersion == Self.backupFormatVersion else {
            throw LocalDataVaultError.backupFormatInvalid("manifest version mismatch")
        }
        guard manifest.emailCount == payload.store.emails.count,
              manifest.totpCount == payload.store.totps.count,
              manifest.fileCount == payload.store.files.count else {
            throw LocalDataVaultError.backupFingerprintMismatch("manifest counts do not match payload")
        }
        let storeData = try Self.canonicalStoreData(payload.store)
        guard Self.sha256Hex(storeData) == manifest.storeSHA256 else {
            throw LocalDataVaultError.backupFingerprintMismatch("store fingerprint mismatch")
        }
        let referencedIds = Set(payload.store.files.map { $0.ref.fileId })
        guard Set(payload.fileBlobs.keys) == referencedIds,
              Set(manifest.fileFingerprints.keys) == referencedIds else {
            throw LocalDataVaultError.backupFingerprintMismatch("blob set does not match file references")
        }
        for (fileId, blob) in payload.fileBlobs {
            guard manifest.fileFingerprints[fileId] == Self.sha256Hex(blob) else {
                throw LocalDataVaultError.backupFingerprintMismatch("blob fingerprint mismatch for \(fileId)")
            }
        }
        let store = try Self.migrateStore(payload.store)

        // ---- Verified: apply atomically-ish (blobs first, records last) ----
        try withLock {
            let fm = FileManager.default
            for (fileId, blob) in payload.fileBlobs {
                let url = filesDirectory.appendingPathComponent("\(fileId).wzen")
                do { try blob.write(to: url, options: [.atomic]) } catch {
                    throw LocalDataVaultError.ioError("cannot restore file blob \(fileId): \(error)")
                }
            }
            var newEmails: [VaultRecordKey: String] = [:]
            var newTotps: [VaultRecordKey: TOTPSecretRecord] = [:]
            var newFiles: [VaultRecordKey: [EncryptedFileRef]] = [:]
            for e in store.emails {
                newEmails[VaultRecordKey(accountId: e.accountId, cipherId: e.cipherId)] = e.email
            }
            for t in store.totps {
                newTotps[VaultRecordKey(accountId: t.accountId, cipherId: t.cipherId)] = t.record
            }
            for f in store.files {
                newFiles[VaultRecordKey(accountId: f.accountId, cipherId: f.cipherId), default: []].append(f.ref)
            }
            emails = newEmails
            totps = newTotps
            fileRefs = newFiles
            try persistLocked()
        }
    }
}
