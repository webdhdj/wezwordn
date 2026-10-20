import Foundation
import Crypto

/// Local emergency-recovery package.
///
/// Scheme: an ephemeral Curve25519 (X25519) key pair is generated per package.
/// ephemeralPrivate x recipientPublic -> shared secret -> HKDF-SHA256
/// (salt = random 32 bytes, info = "WezWordn-EmergencyRecovery-v1") ->
/// AES-256-GCM encryption of the vault key.
/// `ciphertext` in the package is ciphertext || 16-byte GCM tag concatenated.
/// Only the holder of the recipient private key can recover the vault key;
/// a wrong private key fails GCM authentication. There is no server, no
/// waiting period and no revocation in this local design -- those guarantees
/// require a trusted service and are explicitly NOT claimed here.
public struct RecoveryPackage: Codable, Equatable {
    public var version: Int
    public var ephemeralPublicKey: Data
    public var salt: Data
    public var nonce: Data
    public var ciphertext: Data // ciphertext || tag
    public var createdAt: Date
    public var ownerLabel: String

    public init(version: Int, ephemeralPublicKey: Data, salt: Data, nonce: Data,
                ciphertext: Data, createdAt: Date, ownerLabel: String) {
        self.version = version; self.ephemeralPublicKey = ephemeralPublicKey
        self.salt = salt; self.nonce = nonce; self.ciphertext = ciphertext
        self.createdAt = createdAt; self.ownerLabel = ownerLabel
    }
}

public enum EmergencyRecoveryError: Error, Equatable {
    case unsupportedVersion(Int)
    case malformedPackage(String)
    case decryptionFailed
}

public enum EmergencyRecovery {
    public static let currentVersion = 1
    private static let hkdfInfo = Data("WezWordn-EmergencyRecovery-v1".utf8)

    private static func deriveKey(sharedSecret: SharedSecret, salt: Data) -> SymmetricKey {
        sharedSecret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: hkdfInfo, outputByteCount: 32)
    }

    public static func createPackage(vaultKey: Data, recipientPublicKey: Curve25519.KeyAgreement.PublicKey,
                                     ownerLabel: String, createdAt: Date = Date()) throws -> RecoveryPackage {
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: recipientPublicKey)
        let salt = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let key = deriveKey(sharedSecret: shared, salt: salt)
        let nonceData = Data((0..<12).map { _ in UInt8.random(in: 0...255) })
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealed = try AES.GCM.seal(vaultKey, using: key, nonce: nonce)
        // Normalise slices into a fresh, zero-based Data: swift-crypto's
        // SealedBox.ciphertext/tag can be slices whose indices do not start
        // at 0, and subscripting such a Data traps on Linux.
        var combined = Data()
        combined.append(Data(sealed.ciphertext))
        combined.append(Data(sealed.tag))
        return RecoveryPackage(version: currentVersion,
                               ephemeralPublicKey: ephemeral.publicKey.rawRepresentation,
                               salt: salt, nonce: nonceData, ciphertext: combined,
                               createdAt: createdAt, ownerLabel: ownerLabel)
    }

    public static func recoverVaultKey(package: RecoveryPackage, recipientPrivateKey: Curve25519.KeyAgreement.PrivateKey) throws -> Data {
        guard package.version == currentVersion else { throw EmergencyRecoveryError.unsupportedVersion(package.version) }
        guard package.ciphertext.count > 16, package.nonce.count == 12 else {
            throw EmergencyRecoveryError.malformedPackage("ciphertext/nonce length")
        }
        let ephemeralPublic: Curve25519.KeyAgreement.PublicKey
        do { ephemeralPublic = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: package.ephemeralPublicKey) }
        catch { throw EmergencyRecoveryError.malformedPackage("ephemeral public key") }
        let shared = try recipientPrivateKey.sharedSecretFromKeyAgreement(with: ephemeralPublic)
        let key = deriveKey(sharedSecret: shared, salt: package.salt)
        let cipher = Data(package.ciphertext.dropLast(16))
        let tag = Data(package.ciphertext.suffix(16))
        do {
            let nonce = try AES.GCM.Nonce(data: package.nonce)
            let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: cipher, tag: tag)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw EmergencyRecoveryError.decryptionFailed
        }
    }
}
