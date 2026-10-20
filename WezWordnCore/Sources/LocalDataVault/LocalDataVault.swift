import Foundation
import Crypto
import LocalEncryptedStorage
import LocalTOTP
import ExtendedLoginFields

// MARK: - Public record types

/// Composite binding key for every sidecar record. The account component is
/// what guarantees account isolation: records of account A are stored,
/// listed, swept and deleted strictly under A's key space, even if a
/// `cipherId` collides with one of account B's items.
public struct VaultRecordKey: Hashable, Codable, Equatable {
    public var accountId: String
    public var cipherId: String
    public init(accountId: String, cipherId: String) {
        self.accountId = accountId
        self.cipherId = cipherId
    }
}

/// A locally stored TOTP secret bound to one vault item. The secret itself
/// stays inside the encrypted sidecar file; it is never synced through
/// Bitwarden and never logged.
public struct TOTPSecretRecord: Codable, Equatable {
    public var secretBase32: String
    public var issuer: String?
    public var accountName: String
    public var algorithm: OTPAlgorithm
    public var digits: Int
    public var period: Int

    public init(secretBase32: String, issuer: String? = nil, accountName: String,
                algorithm: OTPAlgorithm = .sha1, digits: Int = 6, period: Int = 30) {
        self.secretBase32 = secretBase32
        self.issuer = issuer
        self.accountName = accountName
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
    }

    /// Builds a record from a parsed otpauth:// entry (see LocalTOTP).
    public init(entry: OTPAuthEntry) {
        self.init(secretBase32: entry.secretBase32, issuer: entry.issuer,
                  accountName: entry.account, algorithm: entry.algorithm,
                  digits: entry.digits, period: entry.period)
    }

    /// Generates the current TOTP code with the real RFC 6238 implementation
    /// from LocalTOTP.
    public func currentCode(at date: Date = Date()) throws -> String {
        let secret = try Base32.decode(secretBase32)
        return try OTPGenerator.totp(secret: secret, date: date, period: period,
                                     digits: digits, algorithm: algorithm)
    }
}

/// Reference to one encrypted file held by LocalEncryptedStorage.
/// The file's bytes live at `<vault>/files/<fileId>.wzen`; this record is
/// the metadata needed to find, verify and cascade-delete it.
public struct EncryptedFileRef: Codable, Equatable {
    public var fileId: String
    /// Original display name of the plaintext file.
    public var name: String
    /// Plaintext size in bytes.
    public var size: Int64
    /// Lowercase hex SHA-256 of the plaintext, captured at store time.
    public var sha256: String

    public init(fileId: String, name: String, size: Int64, sha256: String) {
        self.fileId = fileId
        self.name = name
        self.size = size
        self.sha256 = sha256
    }
}

public enum LocalDataVaultError: Error, Equatable {
    /// The sidecar on disk uses a schema newer (or otherwise not migratable)
    /// than this build understands. Data is left untouched.
    case unsupportedSchemaVersion(Int)
    case corruptSidecar(String)
    case fileNotFound(String)
    /// Backup decryption failed: wrong password or tampered package.
    /// Guaranteed: no current data was modified.
    case backupBadPasswordOrCorrupt
    case backupFingerprintMismatch(String)
    case backupFormatInvalid(String)
    case ioError(String)
}

// MARK: - On-disk sidecar representation

/// Array-form Codable snapshot of all sidecar records. Arrays (not a
/// dictionary keyed by a stringified composite key) are used so that any
/// accountId/cipherId characters survive a roundtrip unambiguously.
struct SidecarStore: Codable, Equatable {
    var schemaVersion: Int
    var emails: [EmailEntry] = []
    var totps: [TOTPEntry] = []
    var files: [FileEntry] = []

    struct EmailEntry: Codable, Equatable {
        var accountId: String
        var cipherId: String
        var email: String
    }
    struct TOTPEntry: Codable, Equatable {
        var accountId: String
        var cipherId: String
        var record: TOTPSecretRecord
    }
    struct FileEntry: Codable, Equatable {
        var accountId: String
        var cipherId: String
        var ref: EncryptedFileRef
    }
}

// MARK: - LocalDataVault

/// Local sidecar data vault: binds WezWordn-only data (extra login email,
/// local TOTP secrets, encrypted-file references) to Bitwarden vault items
/// by the composite key (accountId, cipherId), without touching Bitwarden's
/// synced data model.
///
/// Storage layout under `directory`:
///   vault-sidecar.wzen   — SidecarStore JSON, encrypted with
///                          LocalEncryptedStorage (chunked AES-256-GCM,
///                          "WZEN" format) under the KeyProvider key.
///   files/<fileId>.wzen  — referenced encrypted files, same scheme/key.
///
/// Integrity rules:
/// - Every mutation is persisted to the encrypted sidecar immediately.
/// - `schemaVersion` is checked on open; an unknown newer version throws
///   `unsupportedSchemaVersion` and nothing is modified (no silent data
///   loss). Older versions go through `migrateStore` (v1 is current, so
///   the only accepted on-disk version today is 1).
/// - Deleting a cipher cascades: its records AND its encrypted files are
///   removed. `orphanSweep` applies the same cascade to ciphers that a
///   sync/account switch left behind.
/// - Plaintext sidecar JSON only ever exists in short-lived temp files
///   inside the vault directory, deleted on every path.
public final class LocalDataVault {
    public static let currentSchemaVersion = 1
    public static let sidecarFileName = "vault-sidecar.wzen"
    public static let filesDirectoryName = "files"

    private let directory: URL
    let filesDirectory: URL
    private let sidecarURL: URL
    private var keyProvider: KeyProvider
    private let lock = NSLock()

    var emails: [VaultRecordKey: String] = [:]
    var totps: [VaultRecordKey: TOTPSecretRecord] = [:]
    var fileRefs: [VaultRecordKey: [EncryptedFileRef]] = [:]

    /// Opens (or creates) a vault in `directory`. If a sidecar exists it is
    /// decrypted with `keyProvider`'s key — a wrong key throws
    /// `EncryptedFileError.authenticationFailed` and nothing is written.
    public init(directory: URL, keyProvider: KeyProvider) throws {
        self.directory = directory
        self.filesDirectory = directory.appendingPathComponent(Self.filesDirectoryName, isDirectory: true)
        self.sidecarURL = directory.appendingPathComponent(Self.sidecarFileName)
        self.keyProvider = keyProvider
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
        } catch {
            throw LocalDataVaultError.ioError("cannot create vault directory: \(error)")
        }
        if fm.fileExists(atPath: sidecarURL.path) {
            let store = try Self.loadStore(from: sidecarURL, keyProvider: keyProvider)
            emails = Dictionary(uniqueKeysWithValues: store.emails.map {
                (VaultRecordKey(accountId: $0.accountId, cipherId: $0.cipherId), $0.email)
            })
            totps = Dictionary(uniqueKeysWithValues: store.totps.map {
                (VaultRecordKey(accountId: $0.accountId, cipherId: $0.cipherId), $0.record)
            })
            for entry in store.files {
                let key = VaultRecordKey(accountId: entry.accountId, cipherId: entry.cipherId)
                fileRefs[key, default: []].append(entry.ref)
            }
        } else {
            try persistLocked()
        }
    }

    // MARK: Snapshot / persistence (call with lock held, or during init)

    func snapshotLocked() -> SidecarStore {
        var store = SidecarStore(schemaVersion: Self.currentSchemaVersion)
        store.emails = emails.map {
            SidecarStore.EmailEntry(accountId: $0.key.accountId, cipherId: $0.key.cipherId, email: $0.value)
        }.sorted { ($0.accountId, $0.cipherId) < ($1.accountId, $1.cipherId) }
        store.totps = totps.map {
            SidecarStore.TOTPEntry(accountId: $0.key.accountId, cipherId: $0.key.cipherId, record: $0.value)
        }.sorted { ($0.accountId, $0.cipherId) < ($1.accountId, $1.cipherId) }
        store.files = fileRefs.flatMap { (key, refs) in
            refs.map { SidecarStore.FileEntry(accountId: key.accountId, cipherId: key.cipherId, ref: $0) }
        }.sorted { ($0.accountId, $0.cipherId, $0.ref.fileId) < ($1.accountId, $1.cipherId, $1.ref.fileId) }
        return store
    }

    func persistLocked() throws {
        try Self.writeStore(snapshotLocked(), to: sidecarURL, keyProvider: keyProvider)
    }

    static func writeStore(_ store: SidecarStore, to sidecarURL: URL, keyProvider: KeyProvider) throws {
        let fm = FileManager.default
        let dir = sidecarURL.deletingLastPathComponent()
        let plainTmp = dir.appendingPathComponent(".sidecar-plain-\(UUID().uuidString)")
        let encTmp = dir.appendingPathComponent(".sidecar-enc-\(UUID().uuidString)")
        defer {
            try? fm.removeItem(at: plainTmp)
            try? fm.removeItem(at: encTmp)
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(store).write(to: plainTmp, options: [.atomic])
            try LocalEncryptedStorage.encryptFile(at: plainTmp, to: encTmp, keyProvider: keyProvider)
        } catch let e as EncryptedFileError {
            throw e
        } catch {
            throw LocalDataVaultError.ioError("persist failed: \(error)")
        }
        try? fm.removeItem(at: plainTmp)
        // Swap in only after the new sidecar is fully encrypted.
        if fm.fileExists(atPath: sidecarURL.path) {
            do { try fm.removeItem(at: sidecarURL) } catch {
                throw LocalDataVaultError.ioError("cannot replace sidecar: \(error)")
            }
        }
        do { try fm.moveItem(at: encTmp, to: sidecarURL) } catch {
            throw LocalDataVaultError.ioError("cannot install sidecar: \(error)")
        }
    }

    static func loadStore(from sidecarURL: URL, keyProvider: KeyProvider) throws -> SidecarStore {
        let fm = FileManager.default
        let dir = sidecarURL.deletingLastPathComponent()
        let plainTmp = dir.appendingPathComponent(".sidecar-load-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: plainTmp) }
        // A wrong key throws EncryptedFileError.authenticationFailed here.
        try LocalEncryptedStorage.decryptFile(at: sidecarURL, to: plainTmp, keyProvider: keyProvider)
        let data: Data
        do { data = try Data(contentsOf: plainTmp) } catch {
            throw LocalDataVaultError.ioError("cannot read decrypted sidecar: \(error)")
        }
        let raw: SidecarStore
        do { raw = try JSONDecoder().decode(SidecarStore.self, from: data) } catch {
            throw LocalDataVaultError.corruptSidecar("sidecar JSON undecodable")
        }
        return try migrateStore(raw)
    }

    /// Schema gate + migration. v1 is the current (and first) schema, so any
    /// other version is rejected explicitly rather than silently dropped:
    /// a NEWER version was written by a newer build and must be opened by it;
    /// anything below 1 was never a valid sidecar.
    static func migrateStore(_ store: SidecarStore) throws -> SidecarStore {
        // v1 -> v1 (current): no field changes required. Any other version
        // is rejected explicitly — see the doc comment above.
        if store.schemaVersion == currentSchemaVersion { return store }
        throw LocalDataVaultError.unsupportedSchemaVersion(store.schemaVersion)
    }

    func withLock<T>(_ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    // MARK: - Email (ExtendedLoginFields sidecar)

    public func email(accountId: String, cipherId: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return emails[VaultRecordKey(accountId: accountId, cipherId: cipherId)]
    }

    public func setEmail(_ email: String, accountId: String, cipherId: String) throws {
        try withLock {
            emails[VaultRecordKey(accountId: accountId, cipherId: cipherId)] = email
            try persistLocked()
        }
    }

    /// Convenience binding for an `ExtendedLogin`: stores its independent
    /// `email` field under the item's composite key.
    public func setEmail(from login: ExtendedLogin, accountId: String, cipherId: String) throws {
        guard let email = login.email, !email.isEmpty else { return }
        try setEmail(email, accountId: accountId, cipherId: cipherId)
    }

    @discardableResult
    public func removeEmail(accountId: String, cipherId: String) throws -> Bool {
        try withLock {
            let key = VaultRecordKey(accountId: accountId, cipherId: cipherId)
            guard emails.removeValue(forKey: key) != nil else { return false }
            try persistLocked()
            return true
        }
    }

    // MARK: - TOTP secrets

    public func totpRecord(accountId: String, cipherId: String) -> TOTPSecretRecord? {
        lock.lock(); defer { lock.unlock() }
        return totps[VaultRecordKey(accountId: accountId, cipherId: cipherId)]
    }

    public func setTOTP(_ record: TOTPSecretRecord, accountId: String, cipherId: String) throws {
        try withLock {
            totps[VaultRecordKey(accountId: accountId, cipherId: cipherId)] = record
            try persistLocked()
        }
    }

    @discardableResult
    public func removeTOTP(accountId: String, cipherId: String) throws -> Bool {
        try withLock {
            let key = VaultRecordKey(accountId: accountId, cipherId: cipherId)
            guard totps.removeValue(forKey: key) != nil else { return false }
            try persistLocked()
            return true
        }
    }

    // MARK: - Encrypted files

    private func fileURL(for ref: EncryptedFileRef) -> URL {
        filesDirectory.appendingPathComponent("\(ref.fileId).wzen")
    }

    /// Encrypts `plaintext` into the vault's file store and registers its
    /// reference under the composite key. The plaintext file's SHA-256 and
    /// size are captured by streaming, before encryption.
    @discardableResult
    public func storeFile(plaintextAt source: URL, accountId: String, cipherId: String,
                          name: String? = nil) throws -> EncryptedFileRef {
        try withLock {
            let (size, sha) = try Self.fingerprint(ofFileAt: source)
            let ref = EncryptedFileRef(fileId: UUID().uuidString,
                                       name: name ?? source.lastPathComponent,
                                       size: size, sha256: sha)
            let dest = fileURL(for: ref)
            try LocalEncryptedStorage.encryptFile(at: source, to: dest, keyProvider: keyProvider)
            let key = VaultRecordKey(accountId: accountId, cipherId: cipherId)
            fileRefs[key, default: []].append(ref)
            do {
                try persistLocked()
            } catch {
                // Roll back the just-written encrypted file so a failed
                // persist never leaves unreferenced ciphertext behind.
                fileRefs[key]?.removeAll { $0.fileId == ref.fileId }
                try? FileManager.default.removeItem(at: dest)
                throw error
            }
            return ref
        }
    }

    public func fileRefs(accountId: String, cipherId: String) -> [EncryptedFileRef] {
        lock.lock(); defer { lock.unlock() }
        return fileRefs[VaultRecordKey(accountId: accountId, cipherId: cipherId)] ?? []
    }

    /// Decrypts a referenced file to `destination` with the current key.
    public func decryptFile(_ ref: EncryptedFileRef, to destination: URL) throws {
        lock.lock(); defer { lock.unlock() }
        let src = fileURL(for: ref)
        guard FileManager.default.fileExists(atPath: src.path) else {
            throw LocalDataVaultError.fileNotFound(ref.fileId)
        }
        try LocalEncryptedStorage.decryptFile(at: src, to: destination, keyProvider: keyProvider)
    }

    /// Decrypts a referenced file fully into memory (small files / tests).
    public func decryptedData(for ref: EncryptedFileRef) throws -> Data {
        let tmp = directory.appendingPathComponent(".dec-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try decryptFile(ref, to: tmp)
        do { return try Data(contentsOf: tmp) } catch {
            throw LocalDataVaultError.ioError("cannot read decrypted file: \(error)")
        }
    }

    @discardableResult
    public func removeFile(_ ref: EncryptedFileRef, accountId: String, cipherId: String) throws -> Bool {
        try withLock {
            let key = VaultRecordKey(accountId: accountId, cipherId: cipherId)
            guard var refs = fileRefs[key], refs.contains(where: { $0.fileId == ref.fileId }) else { return false }
            refs.removeAll { $0.fileId == ref.fileId }
            fileRefs[key] = refs.isEmpty ? nil : refs
            try? FileManager.default.removeItem(at: fileURL(for: ref))
            try persistLocked()
            return true
        }
    }

    static func fingerprint(ofFileAt url: URL) throws -> (size: Int64, sha256Hex: String) {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw LocalDataVaultError.ioError("cannot open file for fingerprinting")
        }
        defer { try? handle.close() }
        var hasher = SHA256()
        var total: Int64 = 0
        while true {
            let chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
            total += Int64(chunk.count)
        }
        let digest = hasher.finalize()
        return (total, digest.map { String(format: "%02x", $0) }.joined())
    }

    // MARK: - Cascade delete & orphan sweep

    /// Deletes EVERYTHING bound to (accountId, cipherId): the email record,
    /// the TOTP record, all file references and the referenced encrypted
    /// files themselves from disk.
    public func deleteCipher(accountId: String, cipherId: String) throws {
        try withLock {
            let key = VaultRecordKey(accountId: accountId, cipherId: cipherId)
            emails.removeValue(forKey: key)
            totps.removeValue(forKey: key)
            let refs = fileRefs.removeValue(forKey: key) ?? []
            for ref in refs {
                try? FileManager.default.removeItem(at: fileURL(for: ref))
            }
            try persistLocked()
        }
    }

    /// Removes every record (and referenced file) under `accountId` whose
    /// cipherId is not in `liveCipherIds` — the debris left after items are
    /// deleted upstream or a sync prunes the vault. Returns the number of
    /// distinct cipherIds swept. Other accounts are never touched.
    @discardableResult
    public func orphanSweep(accountId: String, liveCipherIds: Set<String>) throws -> Int {
        try withLock {
            var doomed = Set<VaultRecordKey>()
            for key in emails.keys where key.accountId == accountId && !liveCipherIds.contains(key.cipherId) {
                doomed.insert(key)
            }
            for key in totps.keys where key.accountId == accountId && !liveCipherIds.contains(key.cipherId) {
                doomed.insert(key)
            }
            for key in fileRefs.keys where key.accountId == accountId && !liveCipherIds.contains(key.cipherId) {
                doomed.insert(key)
            }
            if doomed.isEmpty { return 0 }
            for key in doomed {
                emails.removeValue(forKey: key)
                totps.removeValue(forKey: key)
                let refs = fileRefs.removeValue(forKey: key) ?? []
                for ref in refs {
                    try? FileManager.default.removeItem(at: fileURL(for: ref))
                }
            }
            try persistLocked()
            return doomed.count
        }
    }

    /// Record counts for one account (diagnostics / UI badges).
    public func counts(accountId: String) -> (emails: Int, totps: Int, files: Int) {
        lock.lock(); defer { lock.unlock() }
        let e = emails.keys.filter { $0.accountId == accountId }.count
        let t = totps.keys.filter { $0.accountId == accountId }.count
        let f = fileRefs.filter { $0.key.accountId == accountId }.values.reduce(0) { $0 + $1.count }
        return (e, t, f)
    }

    // MARK: - Key rotation

    /// Re-encrypts the whole vault under a new storage key: every referenced
    /// encrypted file is rekeyed (old -> new) and finally the sidecar itself
    /// is rewritten under the new key.
    ///
    /// Failure semantics: each file rekey is individually safe (see
    /// `LocalEncryptedStorage.rekeyFile`) — a file whose rekey fails keeps
    /// its old-key ciphertext. If any file fails, all already-rotated files
    /// are best-effort rotated back and the error is rethrown with the
    /// vault still on the old key. After success the old key can no longer
    /// open the sidecar or any file, and this instance uses the new key.
    public func rotateStorageKey(to newKeyProvider: KeyProvider) throws {
        try withLock {
            let oldKey = try keyProvider.encryptionKey()
            let newKey = try newKeyProvider.encryptionKey()
            if oldKey.withUnsafeBytes({ Data($0) }) == newKey.withUnsafeBytes({ Data($0) }) {
                return // Same key: nothing to do.
            }
            let allRefs = fileRefs.values.flatMap { $0 }
            var rotated: [EncryptedFileRef] = []
            do {
                for ref in allRefs {
                    try LocalEncryptedStorage.rekeyFile(at: fileURL(for: ref), oldKey: oldKey, newKey: newKey)
                    rotated.append(ref)
                }
            } catch {
                for ref in rotated {
                    try? LocalEncryptedStorage.rekeyFile(at: fileURL(for: ref), oldKey: newKey, newKey: oldKey)
                }
                throw error
            }
            // Files are on the new key; rewrite the sidecar under it.
            let previousProvider = keyProvider
            keyProvider = newKeyProvider
            do {
                try persistLocked()
            } catch {
                keyProvider = previousProvider
                for ref in allRefs {
                    try? LocalEncryptedStorage.rekeyFile(at: fileURL(for: ref), oldKey: newKey, newKey: oldKey)
                }
                throw error
            }
        }
    }
}
