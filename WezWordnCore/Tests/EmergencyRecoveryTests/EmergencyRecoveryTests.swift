import XCTest
import Crypto
@testable import EmergencyRecovery

final class EmergencyRecoveryTests: XCTestCase {
    func testRoundtrip() throws {
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let vaultKey = Data((0..<32).map { UInt8($0 * 7 % 256) })
        let pkg = try EmergencyRecovery.createPackage(vaultKey: vaultKey, recipientPublicKey: recipient.publicKey, ownerLabel: "Family Emergency Contact")
        XCTAssertEqual(pkg.version, 1)
        XCTAssertEqual(pkg.ownerLabel, "Family Emergency Contact")
        XCTAssertEqual(pkg.ephemeralPublicKey.count, 32)
        XCTAssertEqual(pkg.salt.count, 32)
        XCTAssertEqual(pkg.nonce.count, 12)
        let recovered = try EmergencyRecovery.recoverVaultKey(package: pkg, recipientPrivateKey: recipient)
        XCTAssertEqual(recovered, vaultKey)
    }
    func testPackageCodableRoundtrip() throws {
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let vaultKey = Data(repeating: 0xAB, count: 32)
        let pkg = try EmergencyRecovery.createPackage(vaultKey: vaultKey, recipientPublicKey: recipient.publicKey, ownerLabel: "x")
        let data = try JSONEncoder().encode(pkg)
        let decoded = try JSONDecoder().decode(RecoveryPackage.self, from: data)
        XCTAssertEqual(decoded, pkg)
        XCTAssertEqual(try EmergencyRecovery.recoverVaultKey(package: decoded, recipientPrivateKey: recipient), vaultKey)
    }
    func testWrongPrivateKeyFails() throws {
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let stranger = Curve25519.KeyAgreement.PrivateKey()
        let pkg = try EmergencyRecovery.createPackage(vaultKey: Data(repeating: 1, count: 32), recipientPublicKey: recipient.publicKey, ownerLabel: "x")
        XCTAssertThrowsError(try EmergencyRecovery.recoverVaultKey(package: pkg, recipientPrivateKey: stranger)) {
            XCTAssertEqual($0 as? EmergencyRecoveryError, .decryptionFailed)
        }
    }
    func testTamperedCiphertextFails() throws {
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        var pkg = try EmergencyRecovery.createPackage(vaultKey: Data(repeating: 2, count: 32), recipientPublicKey: recipient.publicKey, ownerLabel: "x")
        // Note: mutate via reconstruction -- in-place `data[i] ^= x` on a
        // bridged Data slice crashed the Linux test runner (Signal 4 in
        // Data._Representation.subscript), so avoid that pattern in tests.
        var ct = [UInt8](pkg.ciphertext); ct[0] ^= 0xFF; pkg.ciphertext = Data(ct)
        XCTAssertThrowsError(try EmergencyRecovery.recoverVaultKey(package: pkg, recipientPrivateKey: recipient))
    }
}
