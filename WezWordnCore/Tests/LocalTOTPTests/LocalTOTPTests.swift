import XCTest
@testable import LocalTOTP

final class LocalTOTPTests: XCTestCase {
    // RFC 6238 Appendix B test vectors, 8 digits, period 30.
    private func check(secretASCII: String, algorithm: OTPAlgorithm,
                       vectors: [(TimeInterval, String)], file: StaticString = #filePath, line: UInt = #line) throws {
        let secret = Data(secretASCII.utf8)
        for (t, expected) in vectors {
            let code = try OTPGenerator.totp(secret: secret, date: Date(timeIntervalSince1970: t), period: 30, digits: 8, algorithm: algorithm)
            XCTAssertEqual(code, expected, "t=\(t) algo=\(algorithm)", file: file, line: line)
        }
    }
    func testRFC6238SHA1() throws {
        // RFC 6238 Appendix B values, cross-checked against the RFC text and
        // an independent Python hmac/hashlib computation.
        try check(secretASCII: "12345678901234567890", algorithm: .sha1, vectors: [
            (59, "94287082"), (1111111109, "07081804"), (1111111111, "14050471"),
            (1234567890, "89005924"), (2000000000, "69279037"), (20000000000, "65353130"),
        ])
    }
    func testRFC6238SHA256() throws {
        try check(secretASCII: "12345678901234567890123456789012", algorithm: .sha256, vectors: [
            (59, "46119246"), (1111111109, "68084774"), (1111111111, "67062674"),
            (1234567890, "91819424"), (2000000000, "90698825"), (20000000000, "77737706"),
        ])
    }
    func testRFC6238SHA512() throws {
        try check(secretASCII: "1234567890123456789012345678901234567890123456789012345678901234", algorithm: .sha512, vectors: [
            (59, "90693936"), (1111111109, "25091201"), (1111111111, "99943326"),
            (1234567890, "93441116"), (2000000000, "38618901"), (20000000000, "47863826"),
        ])
    }
    func testBase32DecodePaddingAndSpaces() throws {
        // "Hello!\xde\xad\xbe\xef" style RFC 4648 vectors: "MY======" = "f", "MZXW6===" = "foo"
        XCTAssertEqual(try Base32.decode("MY======"), Data("f".utf8))
        XCTAssertEqual(try Base32.decode("MZXW6==="), Data("foo".utf8))
        XCTAssertEqual(try Base32.decode("MZXW6"), Data("foo".utf8)) // no padding
        XCTAssertEqual(try Base32.decode("MZ XW 6"), Data("foo".utf8)) // spaces
        XCTAssertEqual(try Base32.decode("mzxw6"), Data("foo".utf8)) // lowercase
        XCTAssertThrowsError(try Base32.decode("MZX*"))
    }
    func testBase32Roundtrip() throws {
        let original = Data("WezWordn-TOTP-secret".utf8)
        XCTAssertEqual(try Base32.decode(Base32.encode(original)), original)
    }
    func testRemainingSeconds() {
        XCTAssertEqual(OTPGenerator.remainingSeconds(date: Date(timeIntervalSince1970: 59), period: 30), 1)
        XCTAssertEqual(OTPGenerator.remainingSeconds(date: Date(timeIntervalSince1970: 60), period: 30), 30)
        XCTAssertEqual(OTPGenerator.remainingSeconds(date: Date(timeIntervalSince1970: 0), period: 30), 30)
    }
    func testHOTPRejectsBadDigits() {
        XCTAssertThrowsError(try OTPGenerator.hotp(secret: Data("x".utf8), counter: 0, digits: 5)) { XCTAssertEqual($0 as? TOTPError, .invalidDigits) }
        XCTAssertThrowsError(try OTPGenerator.hotp(secret: Data("x".utf8), counter: 0, digits: 9))
    }
    func testOTPAuthParserFull() throws {
        let secret = Base32.encode(Data("12345678901234567890".utf8))
        let entry = try OTPAuthParser.parse("otpauth://totp/Example:alice@example.com?secret=\(secret)&issuer=Example&algorithm=SHA256&digits=7&period=60")
        XCTAssertEqual(entry.issuer, "Example")
        XCTAssertEqual(entry.account, "alice@example.com")
        XCTAssertEqual(entry.secret, Data("12345678901234567890".utf8))
        XCTAssertEqual(entry.algorithm, .sha256)
        XCTAssertEqual(entry.digits, 7)
        XCTAssertEqual(entry.period, 60)
        // Code generated from parsed entry must be 7 digits.
        let code = try OTPGenerator.totp(secret: entry.secret, date: Date(timeIntervalSince1970: 59), period: entry.period, digits: entry.digits, algorithm: entry.algorithm)
        XCTAssertEqual(code.count, 7)
    }
    func testOTPAuthParserRejectsInvalid() {
        XCTAssertThrowsError(try OTPAuthParser.parse("https://totp/x?secret=MY======"))
        XCTAssertThrowsError(try OTPAuthParser.parse("otpauth://hotp/x?secret=MY======"))
        XCTAssertThrowsError(try OTPAuthParser.parse("otpauth://totp/x")) { XCTAssertEqual($0 as? TOTPError, .missingSecret) }
        XCTAssertThrowsError(try OTPAuthParser.parse("otpauth://totp/x?secret=MY======&digits=9"))
        XCTAssertThrowsError(try OTPAuthParser.parse("otpauth://totp/x?secret=MY======&algorithm=MD5"))
        XCTAssertThrowsError(try OTPAuthParser.parse("otpauth://totp/x?secret=NOT!BASE32"))
    }
}
