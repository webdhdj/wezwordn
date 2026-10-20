import Foundation
import Crypto

/// PBKDF2 (RFC 8018 §5.2) with HMAC-SHA256 as the PRF, implemented directly
/// over swift-crypto's `HMAC` because swift-crypto intentionally does not
/// ship a PBKDF2 API.
///
/// Definition, for each block index i (1-based):
///   U_1 = PRF(password, salt ‖ INT_32_BE(i))
///   U_n = PRF(password, U_{n-1})
///   T_i = U_1 ⊕ U_2 ⊕ … ⊕ U_iterations
///   DK  = (T_1 ‖ T_2 ‖ …) truncated to `keyLength` bytes.
///
/// Known-answer check (asserted in the test suite):
/// PBKDF2-HMAC-SHA256(password="password", salt="salt", c=1, dkLen=32)
///   = 120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b
public enum PBKDF2 {
    public static func deriveKeySHA256(password: Data, salt: Data, iterations: Int, keyLength: Int = 32) -> Data {
        precondition(iterations >= 1, "PBKDF2 iterations must be >= 1")
        precondition(keyLength >= 1, "PBKDF2 keyLength must be >= 1")
        let key = SymmetricKey(data: password)
        var derived = Data()
        derived.reserveCapacity(keyLength)
        var blockIndex: UInt32 = 1
        while derived.count < keyLength {
            var message = salt
            var be = blockIndex.bigEndian
            message.append(Data(bytes: &be, count: 4))
            var u = Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
            var t = [UInt8](u)
            if iterations > 1 {
                for _ in 1..<iterations {
                    u = Data(HMAC<SHA256>.authenticationCode(for: u, using: key))
                    let ub = [UInt8](u)
                    for i in t.indices { t[i] ^= ub[i] }
                }
            }
            derived.append(Data(t))
            blockIndex += 1
        }
        return Data(derived.prefix(keyLength))
    }

    /// Convenience overload taking the password as a UTF-8 string.
    public static func deriveKeySHA256(password: String, salt: Data, iterations: Int, keyLength: Int = 32) -> Data {
        deriveKeySHA256(password: Data(password.utf8), salt: salt, iterations: iterations, keyLength: keyLength)
    }
}
