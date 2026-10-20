import XCTest
import Crypto
@testable import LocalEncryptedStorage

final class LocalEncryptedStorageTests: XCTestCase {
    var dir: URL!
    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func makeFile(_ name: String, bytes: Int) -> URL {
        let url = dir.appendingPathComponent(name)
        var data = Data(); data.reserveCapacity(bytes)
        for i in 0..<bytes { data.append(UInt8(i % 251)) }
        try! data.write(to: url)
        return url
    }
    private var key: SymmetricKey { SymmetricKey(data: Data((0..<32).map { UInt8($0) })) }
    private var wrongKey: SymmetricKey { SymmetricKey(data: Data((0..<32).map { UInt8(255 - $0) })) }

    func testRoundtripLargerThanChunkSize() throws {
        let src = makeFile("plain.bin", bytes: 10_000)
        let enc = dir.appendingPathComponent("plain.wzen")
        let dec = dir.appendingPathComponent("out.bin")
        try LocalEncryptedStorage.encryptFile(at: src, to: enc, key: key, chunkSize: 1024)
        XCTAssertTrue(FileManager.default.fileExists(atPath: enc.path))
        // Header sanity: magic WZEN.
        let encData = try Data(contentsOf: enc)
        XCTAssertEqual(Array(encData[0..<4]), Array("WZEN".utf8))
        try LocalEncryptedStorage.decryptFile(at: enc, to: dec, key: key)
        XCTAssertEqual(try Data(contentsOf: dec), try Data(contentsOf: src))
    }
    func testRoundtripEmptyAndExactChunk() throws {
        for bytes in [0, 1024] {
            let src = makeFile("p\(bytes).bin", bytes: bytes)
            let enc = dir.appendingPathComponent("p\(bytes).wzen")
            let dec = dir.appendingPathComponent("p\(bytes).out")
            try LocalEncryptedStorage.encryptFile(at: src, to: enc, key: key, chunkSize: 1024)
            try LocalEncryptedStorage.decryptFile(at: enc, to: dec, key: key)
            XCTAssertEqual(try Data(contentsOf: dec), try Data(contentsOf: src), "bytes=\(bytes)")
        }
    }
    func testTamperFailsAndOutputRemoved() throws {
        let src = makeFile("plain.bin", bytes: 3000)
        let enc = dir.appendingPathComponent("t.wzen")
        try LocalEncryptedStorage.encryptFile(at: src, to: enc, key: key, chunkSize: 1024)
        var bytes = [UInt8](try Data(contentsOf: enc))
        bytes[bytes.count - 20] ^= 0xFF // flip a byte inside ciphertext/tag region
        try Data(bytes).write(to: enc)
        let dec = dir.appendingPathComponent("t.out")
        XCTAssertThrowsError(try LocalEncryptedStorage.decryptFile(at: enc, to: dec, key: key))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dec.path), "partial plaintext must be deleted on failure")
    }
    func testWrongKeyFails() throws {
        let src = makeFile("plain.bin", bytes: 500)
        let enc = dir.appendingPathComponent("w.wzen")
        try LocalEncryptedStorage.encryptFile(at: src, to: enc, key: key, chunkSize: 1024)
        let dec = dir.appendingPathComponent("w.out")
        XCTAssertThrowsError(try LocalEncryptedStorage.decryptFile(at: enc, to: dec, key: wrongKey)) {
            XCTAssertEqual($0 as? EncryptedFileError, .authenticationFailed)
        }
    }
    func testNoncesDifferBetweenEncryptions() throws {
        let src = makeFile("plain.bin", bytes: 500)
        let e1 = dir.appendingPathComponent("1.wzen"); let e2 = dir.appendingPathComponent("2.wzen")
        try LocalEncryptedStorage.encryptFile(at: src, to: e1, key: key, chunkSize: 1024)
        try LocalEncryptedStorage.encryptFile(at: src, to: e2, key: key, chunkSize: 1024)
        let d1 = try Data(contentsOf: e1); let d2 = try Data(contentsOf: e2)
        XCTAssertNotEqual(d1, d2)
        XCTAssertNotEqual(d1[5..<17], d2[5..<17]) // baseNonce field differs
    }
    func testKeyProviderRoundtrip() throws {
        let provider = InMemoryKeyProvider(keyData: Data((0..<32).map { UInt8($0 ^ 0x5A) }))
        let src = makeFile("plain.bin", bytes: 2048)
        let enc = dir.appendingPathComponent("k.wzen"); let dec = dir.appendingPathComponent("k.out")
        try LocalEncryptedStorage.encryptFile(at: src, to: enc, keyProvider: provider, chunkSize: 512)
        try LocalEncryptedStorage.decryptFile(at: enc, to: dec, keyProvider: provider)
        XCTAssertEqual(try Data(contentsOf: dec), try Data(contentsOf: src))
    }
}
