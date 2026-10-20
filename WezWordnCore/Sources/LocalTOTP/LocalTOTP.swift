import Foundation
import Crypto

// MARK: - Base32 (RFC 4648)

public enum Base32 {
    private static let alphabet: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    /// Decodes RFC 4648 Base32. Accepts input with or without '=' padding,
    /// ignores whitespace, and is case-insensitive. Throws on invalid characters
    /// or an impossible length.
    public static func decode(_ string: String) throws -> Data {
        let cleaned = string.uppercased().filter { !$0.isWhitespace && $0 != "=" && $0 != "-" }
        if cleaned.isEmpty { throw TOTPError.invalidBase32 }
        var buffer: UInt32 = 0
        var bits = 0
        var out = Data()
        for ch in cleaned {
            guard let idx = alphabet.firstIndex(of: ch) else { throw TOTPError.invalidBase32 }
            buffer = (buffer << 5) | UInt32(idx)
            bits += 5
            if bits >= 8 {
                bits -= 8
                let byte = UInt8((buffer >> UInt32(bits)) & 0xFF)
                out.append(byte)
                buffer &= bits == 0 ? 0 : ((1 << UInt32(bits)) - 1)
            }
        }
        return out
    }

    public static func encode(_ data: Data) -> String {
        if data.isEmpty { return "" }
        var result = ""
        var buffer: UInt32 = 0
        var bits = 0
        for byte in data {
            buffer = (buffer << 8) | UInt32(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                let idx = Int((buffer >> UInt32(bits)) & 0x1F)
                result.append(alphabet[idx])
            }
            buffer &= bits == 0 ? 0 : ((1 << UInt32(bits)) - 1)
        }
        if bits > 0 {
            let idx = Int((buffer << UInt32(5 - bits)) & 0x1F)
            result.append(alphabet[idx])
        }
        while result.count % 8 != 0 { result.append("=") }
        return result
    }
}

// MARK: - Errors / Algorithm

public enum TOTPError: Error, Equatable {
    case invalidBase32
    case invalidDigits
    case invalidPeriod
    case invalidURI(String)
    case missingSecret
}

public enum OTPAlgorithm: String, Codable, Equatable {
    case sha1 = "SHA1"
    case sha256 = "SHA256"
    case sha512 = "SHA512"
}

// MARK: - HOTP (RFC 4226) / TOTP (RFC 6238)

public enum OTPGenerator {
    /// HOTP: HMAC over the 8-byte big-endian counter, dynamic truncation (RFC 4226 §5.3).
    public static func hotp(secret: Data, counter: UInt64, digits: Int = 6, algorithm: OTPAlgorithm = .sha1) throws -> String {
        guard (6...8).contains(digits) else { throw TOTPError.invalidDigits }
        var counterBE = counter.bigEndian
        let counterData = Data(bytes: &counterBE, count: 8)
        let key = SymmetricKey(data: secret)
        let mac: Data
        switch algorithm {
        case .sha1:
            mac = Data(HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: key))
        case .sha256:
            mac = Data(HMAC<SHA256>.authenticationCode(for: counterData, using: key))
        case .sha512:
            mac = Data(HMAC<SHA512>.authenticationCode(for: counterData, using: key))
        }
        let offset = Int(mac[mac.count - 1] & 0x0F)
        let binary: UInt32 = (UInt32(mac[offset] & 0x7F) << 24)
            | (UInt32(mac[offset + 1]) << 16)
            | (UInt32(mac[offset + 2]) << 8)
            | UInt32(mac[offset + 3])
        var modulus: UInt32 = 1
        for _ in 0..<digits { modulus *= 10 }
        let code = binary % modulus
        return String(format: "%0*d", digits, Int(code))
    }

    /// TOTP: counter = floor(unixTime / period) (RFC 6238 §4).
    public static func totp(secret: Data, date: Date, period: Int = 30, digits: Int = 6, algorithm: OTPAlgorithm = .sha1) throws -> String {
        guard period > 0 else { throw TOTPError.invalidPeriod }
        let counter = UInt64(floor(date.timeIntervalSince1970 / Double(period)))
        return try hotp(secret: secret, counter: counter, digits: digits, algorithm: algorithm)
    }

    /// Seconds remaining in the current TOTP window for `date`.
    public static func remainingSeconds(date: Date, period: Int = 30) -> Int {
        guard period > 0 else { return 0 }
        let t = Int(floor(date.timeIntervalSince1970))
        let rem = t % period
        return rem == 0 ? period : period - rem
    }
}

// MARK: - otpauth:// URI parsing

public struct OTPAuthEntry: Equatable {
    public var issuer: String?
    public var account: String
    public var secret: Data
    public var secretBase32: String
    public var algorithm: OTPAlgorithm
    public var digits: Int
    public var period: Int

    public init(issuer: String?, account: String, secret: Data, secretBase32: String,
                algorithm: OTPAlgorithm, digits: Int, period: Int) {
        self.issuer = issuer; self.account = account; self.secret = secret
        self.secretBase32 = secretBase32; self.algorithm = algorithm
        self.digits = digits; self.period = period
    }
}

public enum OTPAuthParser {
    /// Parses `otpauth://totp/[Issuer:]account?secret=...&issuer=...&algorithm=...&digits=...&period=...`.
    /// Rejects non-otpauth schemes, non-TOTP types, missing/invalid secrets,
    /// unsupported algorithms, digits outside 6...8 and non-positive periods.
    public static func parse(_ uri: String) throws -> OTPAuthEntry {
        guard let comps = URLComponents(string: uri),
              comps.scheme?.lowercased() == "otpauth" else {
            throw TOTPError.invalidURI("scheme must be otpauth")
        }
        guard comps.host?.lowercased() == "totp" else {
            throw TOTPError.invalidURI("only totp is supported")
        }
        // Label: path without leading '/', percent-decoded by URLComponents.
        let label = comps.path.hasPrefix("/") ? String(comps.path.dropFirst()) : comps.path
        var labelIssuer: String? = nil
        var account = label
        if let colon = label.firstIndex(of: ":") {
            labelIssuer = String(label[label.startIndex..<colon])
            account = String(label[label.index(after: colon)...])
        }
        if account.isEmpty { throw TOTPError.invalidURI("empty account label") }

        let query = Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name.lowercased(), $0.value ?? "") })
        guard let secretStr = query["secret"], !secretStr.isEmpty else { throw TOTPError.missingSecret }
        let secret: Data
        do { secret = try Base32.decode(secretStr) } catch { throw TOTPError.invalidURI("secret is not valid Base32") }
        if secret.isEmpty { throw TOTPError.missingSecret }

        let issuer = query["issuer"] ?? labelIssuer
        var algorithm: OTPAlgorithm = .sha1
        if let a = query["algorithm"] {
            guard let parsed = OTPAlgorithm(rawValue: a.uppercased()) else {
                throw TOTPError.invalidURI("unsupported algorithm: \(a)")
            }
            algorithm = parsed
        }
        var digits = 6
        if let d = query["digits"] {
            guard let v = Int(d), (6...8).contains(v) else { throw TOTPError.invalidDigits }
            digits = v
        }
        var period = 30
        if let p = query["period"] {
            guard let v = Int(p), v > 0 else { throw TOTPError.invalidPeriod }
            period = v
        }
        return OTPAuthEntry(issuer: issuer, account: account, secret: secret,
                            secretBase32: secretStr, algorithm: algorithm, digits: digits, period: period)
    }
}
