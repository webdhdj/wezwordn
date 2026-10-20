import XCTest
import Crypto
@testable import SecureSharing

final class SecureSharingTests: XCTestCase {
    private var sample: ShareableItem {
        ShareableItem(title: "Example Login", username: "wesam", email: "wesam@example.com",
                      password: "Sup3rSecret!", notes: "shared note", url: "https://example.com")
    }
    func testRoundtrip() throws {
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let pkg = try SecureSharing.createPackage(item: sample, recipientPublicKey: recipient.publicKey)
        XCTAssertTrue(pkg.fingerprintIsValid)
        XCTAssertEqual(pkg.fingerprint.count, 64)
        let opened = try SecureSharing.openPackage(pkg, recipientPrivateKey: recipient)
        XCTAssertEqual(opened, sample)
    }
    func testExportImportWezshareData() throws {
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        // Whole-second date: .wezshare JSON uses ISO-8601 (second precision),
        // so a sub-second createdAt would not compare equal after roundtrip.
        let pkg = try SecureSharing.createPackage(item: sample, recipientPublicKey: recipient.publicKey, createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try SecureSharing.exportData(pkg)
        let imported = try SecureSharing.importData(data)
        XCTAssertEqual(imported, pkg)
        XCTAssertEqual(try SecureSharing.openPackage(imported, recipientPrivateKey: recipient), sample)
    }
    func testTamperFailsFingerprintOrDecryption() throws {
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        var pkg = try SecureSharing.createPackage(item: sample, recipientPublicKey: recipient.publicKey)
        var ct = [UInt8](pkg.ciphertext); ct[ct.count - 1] ^= 0xFF; pkg.ciphertext = Data(ct)
        XCTAssertFalse(pkg.fingerprintIsValid)
        XCTAssertThrowsError(try SecureSharing.openPackage(pkg, recipientPrivateKey: recipient)) {
            XCTAssertEqual($0 as? SecureSharingError, .fingerprintMismatch)
        }
    }
    func testWrongRecipientFails() throws {
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let stranger = Curve25519.KeyAgreement.PrivateKey()
        let pkg = try SecureSharing.createPackage(item: sample, recipientPublicKey: recipient.publicKey)
        XCTAssertThrowsError(try SecureSharing.openPackage(pkg, recipientPrivateKey: stranger)) {
            XCTAssertEqual($0 as? SecureSharingError, .decryptionFailed)
        }
    }
}
