import Foundation
import Crypto

/// Encrypted single-item sharing package (`.wezshare`, JSON encoded).
///
/// Same envelope scheme as EmergencyRecovery, independently implemented for
/// this module: ephemeral X25519 -> HKDF-SHA256 (info
/// "WezWordn-SecureSharing-v1") -> AES-256-GCM over the JSON-serialised item.
/// `ciphertext` is ciphertext || 16-byte GCM tag.
/// `fingerprint` = lowercase hex SHA-256(ephemeralPublicKey || salt || nonce
/// || ciphertext): a non-secret integrity/display value the sender and
/// recipient can compare out-of-band before import. Import verifies the
/// fingerprint AND the GCM tag; either failure rejects the package.
/// Once a recipient decrypts a copy, it cannot be revoked from them -- this
/// is documented behaviour, not a limitation we claim to solve.
public struct ShareableItem: Codable, Equatable {
    public var title: String
    public var username: String?
    public var email: String?
    public var password: String?
    public var notes: String?
    public var url: String?
    public init(title: String, username: String? = nil, email: String? = nil,
                password: String? = nil, notes: String? = nil, url: String? = nil) {
        self.title = title; self.username = username; self.email = email
        self.password = password; self.notes = notes; self.url = url
    }
}

public struct SharePackage: Codable, Equatable {
    public var version: Int
    public var ephemeralPublicKey: Data
    public var salt: Data
    public var nonce: Data
    public var ciphertext: Data // ciphertext || tag
    public var createdAt: Date
    public var fingerprint: String

    public static func computeFingerprint(ephemeralPublicKey: Data, salt: Data, nonce: Data, ciphertext: Data) -> String {
        var hasher = SHA256()
        hasher.update(data: ephemeralPublicKey)
        hasher.update(data: salt)
        hasher.update(data: nonce)
        hasher.update(data: ciphertext)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public var fingerprintIsValid: Bool {
        Self.computeFingerprint(ephemeralPublicKey: ephemeralPublicKey, salt: salt, nonce: nonce, ciphertext: ciphertext) == fingerprint
    }
}

public enum SecureSharingError: Error, Equatable {
    case unsupportedVersion(Int)
    case fingerprintMismatch
    case malformedPackage(String)
    case decryptionFailed
}

public enum SecureSharing {
    public static let currentVersion = 1
    public static let fileExtension = "wezshare"
    private static let hkdfInfo = Data("WezWordn-SecureSharing-v1".utf8)

    private static func deriveKey(sharedSecret: SharedSecret, salt: Data) -> SymmetricKey {
        sharedSecret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: hkdfInfo, outputByteCount: 32)
    }

    public static func createPackage(item: ShareableItem, recipientPublicKey: Curve25519.KeyAgreement.PublicKey,
                                     createdAt: Date = Date()) throws -> SharePackage {
        let payload = try JSONEncoder().encode(item)
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: recipientPublicKey)
        let salt = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let key = deriveKey(sharedSecret: shared, salt: salt)
        let nonceData = Data((0..<12).map { _ in UInt8.random(in: 0...255) })
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealed = try AES.GCM.seal(payload, using: key, nonce: nonce)
        var combined = Data()
        combined.append(Data(sealed.ciphertext))
        combined.append(Data(sealed.tag))
        let eph = ephemeral.publicKey.rawRepresentation
        let fp = SharePackage.computeFingerprint(ephemeralPublicKey: eph, salt: salt, nonce: nonceData, ciphertext: combined)
        return SharePackage(version: currentVersion, ephemeralPublicKey: eph, salt: salt,
                            nonce: nonceData, ciphertext: combined, createdAt: createdAt, fingerprint: fp)
    }

    public static func openPackage(_ package: SharePackage, recipientPrivateKey: Curve25519.KeyAgreement.PrivateKey) throws -> ShareableItem {
        guard package.version == currentVersion else { throw SecureSharingError.unsupportedVersion(package.version) }
        guard package.fingerprintIsValid else { throw SecureSharingError.fingerprintMismatch }
        guard package.ciphertext.count > 16, package.nonce.count == 12 else {
            throw SecureSharingError.malformedPackage("ciphertext/nonce length")
        }
        let ephemeralPublic: Curve25519.KeyAgreement.PublicKey
        do { ephemeralPublic = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: package.ephemeralPublicKey) }
        catch { throw SecureSharingError.malformedPackage("ephemeral public key") }
        let shared = try recipientPrivateKey.sharedSecretFromKeyAgreement(with: ephemeralPublic)
        let key = deriveKey(sharedSecret: shared, salt: package.salt)
        let plain: Data
        do {
            let nonce = try AES.GCM.Nonce(data: package.nonce)
            let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: Data(package.ciphertext.dropLast(16)), tag: Data(package.ciphertext.suffix(16)))
            plain = try AES.GCM.open(box, using: key)
        } catch { throw SecureSharingError.decryptionFailed }
        do { return try JSONDecoder().decode(ShareableItem.self, from: plain) }
        catch { throw SecureSharingError.malformedPackage("payload JSON") }
    }

    /// Serialises a package to `.wezshare` JSON data.
    public static func exportData(_ package: SharePackage) throws -> Data {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        return try enc.encode(package)
    }

    public static func importData(_ data: Data) throws -> SharePackage {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(SharePackage.self, from: data)
    }
}
