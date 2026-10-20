import XCTest
import Crypto
@testable import LocalDataVault
import LocalEncryptedStorage
import LocalTOTP

final class LocalDataVaultTests: XCTestCase {
    var dir: URL!
    let keyA = InMemoryKeyProvider(keyData: Data((0..<32).map { UInt8($0) }))
    let keyB = InMemoryKeyProvider(keyData: Data((0..<32).map { UInt8(255 - $0) }))

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ldv-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func makeVault(key: InMemoryKeyProvider? = nil) throws -> LocalDataVault {
        try LocalDataVault(directory: dir, keyProvider: key ?? keyA)
    }

    private func makePlaintext(_ name: String, _ contents: String) -> URL {
        let url = dir.appendingPathComponent(name)
        try! Data(contents.utf8).write(to: url)
        return url
    }

    private var sampleTOTP: TOTPSecretRecord {
        TOTPSecretRecord(secretBase32: "JBSWY3DPEHPK3PXP", issuer: "Example",
                         accountName: "user@example.com", algorithm: .sha1, digits: 6, period: 30)
    }

    // MARK: - Binding: set/get, persistence, isolation

    func testEmailSetGetAndPersistenceAcrossReopen() throws {
        let vault = try makeVault()
        try vault.setEmail("extra@example.com", accountId: "acct1", cipherId: "cipher1")
        XCTAssertEqual(vault.email(accountId: "acct1", cipherId: "cipher1"), "extra@example.com")
        XCTAssertNil(vault.email(accountId: "acct1", cipherId: "other"))
        // Re-login / app update simulation: a fresh instance over the same
        // directory must see everything.
        let reopened = try makeVault()
        XCTAssertEqual(reopened.email(accountId: "acct1", cipherId: "cipher1"), "extra@example.com")
        // On-disk sidecar is ciphertext, not JSON: the plaintext email must
        // not appear anywhere in the raw sidecar bytes.
        let raw = try Data(contentsOf: dir.appendingPathComponent("vault-sidecar.wzen"))
        XCTAssertFalse(String(decoding: raw, as: UTF8.self).contains("extra@example.com"))
    }

    func testAccountIsolationWithSameCipherId() throws {
        let vault = try makeVault()
        try vault.setEmail("a@example.com", accountId: "A", cipherId: "shared-id")
        try vault.setEmail("b@example.com", accountId: "B", cipherId: "shared-id")
        try vault.setTOTP(sampleTOTP, accountId: "A", cipherId: "shared-id")
        XCTAssertEqual(vault.email(accountId: "A", cipherId: "shared-id"), "a@example.com")
        XCTAssertEqual(vault.email(accountId: "B", cipherId: "shared-id"), "b@example.com")
        XCTAssertNotNil(vault.totpRecord(accountId: "A", cipherId: "shared-id"))
        XCTAssertNil(vault.totpRecord(accountId: "B", cipherId: "shared-id"))
        // Deleting A's cipher must not touch B's records under the same id.
        try vault.deleteCipher(accountId: "A", cipherId: "shared-id")
        XCTAssertNil(vault.email(accountId: "A", cipherId: "shared-id"))
        XCTAssertEqual(vault.email(accountId: "B", cipherId: "shared-id"), "b@example.com")
    }

    func testTOTPRecordRoundtripAndCodeGeneration() throws {
        let vault = try makeVault()
        try vault.setTOTP(sampleTOTP, accountId: "acct1", cipherId: "cipher1")
        let reopened = try makeVault()
        let record = try XCTUnwrap(reopened.totpRecord(accountId: "acct1", cipherId: "cipher1"))
        XCTAssertEqual(record, sampleTOTP)
        // The stored record generates the same code as the raw LocalTOTP API.
        let secret = try Base32.decode("JBSWY3DPEHPK3PXP")
        let date = Date(timeIntervalSince1970: 59)
        let expected = try OTPGenerator.totp(secret: secret, date: date, period: 30, digits: 6, algorithm: .sha1)
        XCTAssertEqual(try record.currentCode(at: date), expected)
        XCTAssertEqual(expected.count, 6)
    }

    func testFileStoreRefFingerprintAndDecrypt() throws {
        let vault = try makeVault()
        let plain = makePlaintext("note.txt", "top secret contents")
        let ref = try vault.storeFile(plaintextAt: plain, accountId: "acct1", cipherId: "cipher1")
        XCTAssertEqual(ref.name, "note.txt")
        XCTAssertEqual(ref.size, Int64("top secret contents".utf8.count))
        // SHA-256 of plaintext, computed independently via swift-crypto.
        let expectedSHA = SHA256.hash(data: Data("top secret contents".utf8))
            .map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(ref.sha256, expectedSHA)
        let refs = vault.fileRefs(accountId: "acct1", cipherId: "cipher1")
        XCTAssertEqual(refs, [ref])
        XCTAssertEqual(try vault.decryptedData(for: ref), Data("top secret contents".utf8))
        // The stored file on disk is a WZEN ciphertext container.
        let stored = try Data(contentsOf: dir.appendingPathComponent("files/\(ref.fileId).wzen"))
        XCTAssertEqual(Array(stored[0..<4]), Array("WZEN".utf8))
        XCTAssertFalse(String(decoding: stored, as: UTF8.self).contains("top secret"))
    }

    // MARK: - Cascade delete & orphan sweep

    func testDeleteCipherCascadesRecordsAndFiles() throws {
        let vault = try makeVault()
        try vault.setEmail("x@example.com", accountId: "acct1", cipherId: "c1")
        try vault.setTOTP(sampleTOTP, accountId: "acct1", cipherId: "c1")
        let plain = makePlaintext("a.bin", "payload")
        let ref = try vault.storeFile(plaintextAt: plain, accountId: "acct1", cipherId: "c1")
        let fileOnDisk = dir.appendingPathComponent("files/\(ref.fileId).wzen")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileOnDisk.path))

        try vault.deleteCipher(accountId: "acct1", cipherId: "c1")
        XCTAssertNil(vault.email(accountId: "acct1", cipherId: "c1"))
        XCTAssertNil(vault.totpRecord(accountId: "acct1", cipherId: "c1"))
        XCTAssertTrue(vault.fileRefs(accountId: "acct1", cipherId: "c1").isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileOnDisk.path))
        let counts = vault.counts(accountId: "acct1")
        XCTAssertEqual(counts.emails, 0); XCTAssertEqual(counts.totps, 0); XCTAssertEqual(counts.files, 0)
        // The cascade is persisted, not just in memory.
        let reopened = try makeVault()
        XCTAssertNil(reopened.email(accountId: "acct1", cipherId: "c1"))
    }

    func testOrphanSweepRemovesOnlyDeadCiphersOfThatAccount() throws {
        let vault = try makeVault()
        for cid in ["live1", "dead1", "dead2"] {
            try vault.setEmail("\(cid)@example.com", accountId: "acct1", cipherId: cid)
        }
        try vault.setEmail("dead1@b.example", accountId: "acct2", cipherId: "dead1")
        let plain = makePlaintext("s.bin", "sweep me")
        let ref = try vault.storeFile(plaintextAt: plain, accountId: "acct1", cipherId: "dead2")
        let fileOnDisk = dir.appendingPathComponent("files/\(ref.fileId).wzen")

        let swept = try vault.orphanSweep(accountId: "acct1", liveCipherIds: ["live1"])
        XCTAssertEqual(swept, 2)
        XCTAssertEqual(vault.email(accountId: "acct1", cipherId: "live1"), "live1@example.com")
        XCTAssertNil(vault.email(accountId: "acct1", cipherId: "dead1"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileOnDisk.path))
        // Account 2's record under an identical cipherId is untouched.
        XCTAssertEqual(vault.email(accountId: "acct2", cipherId: "dead1"), "dead1@b.example")
        // Sweeping again is a no-op.
        XCTAssertEqual(try vault.orphanSweep(accountId: "acct1", liveCipherIds: ["live1"]), 0)
    }

    // MARK: - Schema gate

    func testUnsupportedSchemaVersionIsRejectedNotDropped() throws {
        let vault = try makeVault()
        try vault.setEmail("keep@example.com", accountId: "acct1", cipherId: "c1")
        // Hand-craft a sidecar with a future schema version, encrypted with
        // the correct key, and swap it in.
        let future = SidecarStore(schemaVersion: 99)
        let plainTmp = dir.appendingPathComponent("future.json")
        let encTmp = dir.appendingPathComponent("future.wzen")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(future).write(to: plainTmp)
        try LocalEncryptedStorage.encryptFile(at: plainTmp, to: encTmp, keyProvider: keyA)
        let sidecar = dir.appendingPathComponent("vault-sidecar.wzen")
        try FileManager.default.removeItem(at: sidecar)
        try FileManager.default.moveItem(at: encTmp, to: sidecar)
        XCTAssertThrowsError(try makeVault()) { error in
            XCTAssertEqual(error as? LocalDataVaultError, .unsupportedSchemaVersion(99))
        }
    }

    func testWrongKeyCannotOpenVault() throws {
        let vault = try makeVault()
        try vault.setEmail("x@example.com", accountId: "acct1", cipherId: "c1")
        XCTAssertThrowsError(try makeVault(key: keyB)) { error in
            XCTAssertEqual(error as? EncryptedFileError, .authenticationFailed)
        }
    }

    // MARK: - Key rotation

    func testKeyRotationOldKeyFailsNewKeyReadsEverything() throws {
        let vault = try makeVault()
        try vault.setEmail("rot@example.com", accountId: "acct1", cipherId: "c1")
        try vault.setTOTP(sampleTOTP, accountId: "acct1", cipherId: "c1")
        let plain = makePlaintext("rot.bin", "rotate this payload")
        let ref = try vault.storeFile(plaintextAt: plain, accountId: "acct1", cipherId: "c1")

        try vault.rotateStorageKey(to: keyB)
        // Same instance now works on the new key.
        XCTAssertEqual(try vault.decryptedData(for: ref), Data("rotate this payload".utf8))
        // Old key can no longer open the vault at all.
        XCTAssertThrowsError(try makeVault(key: keyA))
        // New key opens it and every record/file survived.
        let rotated = try makeVault(key: keyB)
        XCTAssertEqual(rotated.email(accountId: "acct1", cipherId: "c1"), "rot@example.com")
        XCTAssertEqual(rotated.totpRecord(accountId: "acct1", cipherId: "c1"), sampleTOTP)
        XCTAssertEqual(try rotated.decryptedData(for: ref), Data("rotate this payload".utf8))
    }

    func testRekeyFileWithWrongOldKeyLeavesOriginalUntouched() throws {
        let vault = try makeVault()
        let plain = makePlaintext("k.bin", "original bytes")
        let ref = try vault.storeFile(plaintextAt: plain, accountId: "acct1", cipherId: "c1")
        let stored = dir.appendingPathComponent("files/\(ref.fileId).wzen")
        let before = try Data(contentsOf: stored)
        XCTAssertThrowsError(try LocalEncryptedStorage.rekeyFile(
            at: stored, oldKey: try keyB.encryptionKey(), newKey: try keyB.encryptionKey()))
        XCTAssertEqual(try Data(contentsOf: stored), before)
        XCTAssertEqual(try vault.decryptedData(for: ref), Data("original bytes".utf8))
    }

    // MARK: - PBKDF2 known answers

    func testPBKDF2KnownVectors() {
        // RFC-style published PBKDF2-HMAC-SHA256 vectors, dkLen 32.
        let v1 = PBKDF2.deriveKeySHA256(password: "password", salt: Data("salt".utf8), iterations: 1)
        XCTAssertEqual(v1.map { String(format: "%02x", $0) }.joined(),
                       "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
        let v2 = PBKDF2.deriveKeySHA256(password: "password", salt: Data("salt".utf8), iterations: 2)
        XCTAssertEqual(v2.map { String(format: "%02x", $0) }.joined(),
                       "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43")
        let v4096 = PBKDF2.deriveKeySHA256(password: "password", salt: Data("salt".utf8), iterations: 4096)
        XCTAssertEqual(v4096.map { String(format: "%02x", $0) }.joined(),
                       "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a")
    }

    // MARK: - Encrypted backup

    private func populate(_ vault: LocalDataVault) throws -> EncryptedFileRef {
        try vault.setEmail("backup@example.com", accountId: "acct1", cipherId: "c1")
        try vault.setTOTP(sampleTOTP, accountId: "acct1", cipherId: "c1")
        let plain = makePlaintext("doc.txt", "backup file body")
        return try vault.storeFile(plaintextAt: plain, accountId: "acct1", cipherId: "c1")
    }

    func testBackupRoundtripAfterFullWipe() throws {
        let vault = try makeVault()
        let ref = try populate(vault)
        let backupURL = dir.appendingPathComponent("backup.wezbackup")
        try vault.exportBackup(password: "correct horse battery staple", iterations: 1_000, to: backupURL)
        // The backup file itself must not leak plaintext records.
        let backupRaw = try Data(contentsOf: backupURL)
        XCTAssertFalse(String(decoding: backupRaw, as: UTF8.self).contains("backup@example.com"))

        // Full wipe: remove the vault directory contents, recreate fresh.
        let backupCopy = FileManager.default.temporaryDirectory.appendingPathComponent("bk-\(UUID().uuidString).wezbackup")
        try FileManager.default.copyItem(at: backupURL, to: backupCopy)
        try FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let restored = try makeVault()
        XCTAssertNil(restored.email(accountId: "acct1", cipherId: "c1"))
        try restored.importBackup(password: "correct horse battery staple", from: backupCopy)
        XCTAssertEqual(restored.email(accountId: "acct1", cipherId: "c1"), "backup@example.com")
        XCTAssertEqual(restored.totpRecord(accountId: "acct1", cipherId: "c1"), sampleTOTP)
        let refs = restored.fileRefs(accountId: "acct1", cipherId: "c1")
        XCTAssertEqual(refs, [ref])
        // The restored blob decrypts with the vault's current storage key.
        XCTAssertEqual(try restored.decryptedData(for: ref), Data("backup file body".utf8))
        // And everything survives a reopen.
        let reopened = try makeVault()
        XCTAssertEqual(reopened.email(accountId: "acct1", cipherId: "c1"), "backup@example.com")
        try? FileManager.default.removeItem(at: backupCopy)
    }

    func testBackupWrongPasswordFailsAndLeavesCurrentDataUntouched() throws {
        let vault = try makeVault()
        _ = try populate(vault)
        let backupURL = dir.appendingPathComponent("backup.wezbackup")
        try vault.exportBackup(password: "right-password", iterations: 1_000, to: backupURL)
        // Change current data after the export.
        try vault.setEmail("current@example.com", accountId: "acct9", cipherId: "c9")

        XCTAssertThrowsError(try vault.importBackup(password: "wrong-password", from: backupURL)) { error in
            XCTAssertEqual(error as? LocalDataVaultError, .backupBadPasswordOrCorrupt)
        }
        // Nothing was restored, nothing was lost.
        XCTAssertEqual(vault.email(accountId: "acct9", cipherId: "c9"), "current@example.com")
        XCTAssertEqual(vault.email(accountId: "acct1", cipherId: "c1"), "backup@example.com")
        let counts = vault.counts(accountId: "acct1")
        XCTAssertEqual(counts.files, 1)
        let reopened = try makeVault()
        XCTAssertEqual(reopened.email(accountId: "acct9", cipherId: "c9"), "current@example.com")
    }
}
