import Foundation
import Crypto

/// Chunked, streaming AES-256-GCM file encryption.
///
/// On-disk format (all integers big-endian):
///   Header:
///     magic      4 bytes  ASCII "WZEN"
///     version    1 byte   0x01
///     baseNonce 12 bytes  cryptographically random, fresh per encryption
///     chunkSize  4 bytes  UInt32, plaintext bytes per chunk (1...16 MiB)
///   Then one record per chunk, counter i = 0, 1, 2, ...:
///     plainLen   4 bytes  UInt32; 1...chunkSize for a data chunk,
///                         0 marks the explicit end-of-stream record (no
///                         ciphertext/tag follow it) and MUST be present --
///                         a file without it is treated as truncated/corrupt.
///     ciphertext plainLen bytes, followed by the 16-byte GCM tag.
///   Chunk nonce: baseNonce with its last 8 bytes XORed with the big-endian
///   UInt64 chunk counter (first 4 bytes unchanged). Because baseNonce is
///   random per file and the counter is unique per chunk within the file,
///   a (key, nonce) pair is never reused across chunks or files.
/// Authentication: each chunk is independently authenticated by its GCM tag;
/// any tampering, wrong key, or truncation fails decryption and the partial
/// plaintext output file is deleted.
public enum EncryptedFileError: Error, Equatable {
    case badMagic
    case unsupportedVersion(UInt8)
    case invalidChunkSize
    case invalidKeySize
    case truncated
    case authenticationFailed
    case ioError(String)
}

public protocol KeyProvider {
    func encryptionKey() throws -> SymmetricKey
}

/// In-memory key provider for tests / non-Keychain use. Production iOS code
/// supplies a Keychain-backed provider with the same protocol.
public struct InMemoryKeyProvider: KeyProvider {
    private let keyData: Data
    public init(keyData: Data) { self.keyData = keyData }
    public init() { self.keyData = Data((0..<32).map { _ in UInt8.random(in: 0...255) }) }
    public func encryptionKey() throws -> SymmetricKey {
        guard keyData.count == 32 else { throw EncryptedFileError.invalidKeySize }
        return SymmetricKey(data: keyData)
    }
    public var rawKeyData: Data { keyData }
}

public enum LocalEncryptedStorage {
    public static let magic: [UInt8] = Array("WZEN".utf8)
    public static let version: UInt8 = 1
    public static let defaultChunkSize = 64 * 1024

    static func chunkNonce(baseNonce: Data, counter: UInt64) -> AES.GCM.Nonce {
        var nonce = [UInt8](baseNonce)
        var c = counter.bigEndian
        let counterBytes = Data(bytes: &c, count: 8)
        for i in 0..<8 { nonce[4 + i] ^= counterBytes[i] }
        // swiftlint:disable:next force_try
        return try! AES.GCM.Nonce(data: Data(nonce))
    }

    public static func encryptFile(at source: URL, to destination: URL, key: SymmetricKey, chunkSize: Int = defaultChunkSize) throws {
        guard key.withUnsafeBytes({ $0.count }) == 32 else { throw EncryptedFileError.invalidKeySize }
        guard chunkSize >= 1 && chunkSize <= 16 * 1024 * 1024 else { throw EncryptedFileError.invalidChunkSize }
        let baseNonceData = Data((0..<12).map { _ in UInt8.random(in: 0...255) })
        do {
_ = FileManager.default.createFile(atPath: destination.path, contents: nil)
            guard let reader = try? FileHandle(forReadingFrom: source),
                  let writer = try? FileHandle(forWritingTo: destination) else {
                throw EncryptedFileError.ioError("cannot open source or destination")
            }
            defer { try? reader.close(); try? writer.close() }
            var header = Data(magic)
            header.append(version)
            header.append(baseNonceData)
            var cs = UInt32(chunkSize).bigEndian
            header.append(Data(bytes: &cs, count: 4))
            try writer.write(contentsOf: header)

            var counter: UInt64 = 0
            while true {
                let chunk = try reader.read(upToCount: chunkSize) ?? Data()
                if chunk.isEmpty { break }
                let nonce = chunkNonce(baseNonce: baseNonceData, counter: counter)
                let sealed = try AES.GCM.seal(chunk, using: key, nonce: nonce)
                var len = UInt32(chunk.count).bigEndian
                try writer.write(contentsOf: Data(bytes: &len, count: 4))
                try writer.write(contentsOf: sealed.ciphertext)
                try writer.write(contentsOf: sealed.tag)
                counter += 1
            }
            // Explicit end-of-stream marker: plainLen == 0.
            var zero = UInt32(0).bigEndian
            try writer.write(contentsOf: Data(bytes: &zero, count: 4))
            try writer.synchronize()
        } catch let e as EncryptedFileError {
            try? FileManager.default.removeItem(at: destination)
            throw e
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw EncryptedFileError.ioError(String(describing: error))
        }
    }

    public static func encryptFile(at source: URL, to destination: URL, keyProvider: KeyProvider, chunkSize: Int = defaultChunkSize) throws {
        try encryptFile(at: source, to: destination, key: try keyProvider.encryptionKey(), chunkSize: chunkSize)
    }

    public static func decryptFile(at source: URL, to destination: URL, key: SymmetricKey) throws {
        guard key.withUnsafeBytes({ $0.count }) == 32 else { throw EncryptedFileError.invalidKeySize }
        do {
            guard let reader = try? FileHandle(forReadingFrom: source) else {
                throw EncryptedFileError.ioError("cannot open encrypted file")
            }
            defer { try? reader.close() }
            let header = try reader.read(upToCount: 21) ?? Data()
            guard header.count == 21 else { throw EncryptedFileError.truncated }
            guard Array(header[0..<4]) == magic else { throw EncryptedFileError.badMagic }
            guard header[4] == version else { throw EncryptedFileError.unsupportedVersion(header[4]) }
            let baseNonce = Data(header[5..<17])
            let chunkSize = Int(header[17..<21].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
            guard chunkSize >= 1 && chunkSize <= 16 * 1024 * 1024 else { throw EncryptedFileError.invalidChunkSize }

_ = FileManager.default.createFile(atPath: destination.path, contents: nil)
            guard let writer = try? FileHandle(forWritingTo: destination) else {
                throw EncryptedFileError.ioError("cannot open destination")
            }
            var closed = false
            defer { if !closed { try? writer.close() } }

            var counter: UInt64 = 0
            while true {
                let lenData = try reader.read(upToCount: 4) ?? Data()
                guard lenData.count == 4 else { throw EncryptedFileError.truncated }
                let plainLen = Int(lenData.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
                if plainLen == 0 { break } // end-of-stream marker
                guard plainLen <= chunkSize else { throw EncryptedFileError.truncated }
                let cipher = try reader.read(upToCount: plainLen) ?? Data()
                let tag = try reader.read(upToCount: 16) ?? Data()
                guard cipher.count == plainLen && tag.count == 16 else { throw EncryptedFileError.truncated }
                let nonce = chunkNonce(baseNonce: baseNonce, counter: counter)
                let box: AES.GCM.SealedBox
                do { box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: cipher, tag: tag) }
                catch { throw EncryptedFileError.authenticationFailed }
                let plain: Data
                do { plain = try AES.GCM.open(box, using: key) }
                catch { throw EncryptedFileError.authenticationFailed }
                try writer.write(contentsOf: plain)
                counter += 1
            }
            try writer.synchronize()
            try writer.close(); closed = true
        } catch let e as EncryptedFileError {
            try? FileManager.default.removeItem(at: destination)
            throw e
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw EncryptedFileError.ioError(String(describing: error))
        }
    }

    public static func decryptFile(at source: URL, to destination: URL, keyProvider: KeyProvider) throws {
        try decryptFile(at: source, to: destination, key: try keyProvider.encryptionKey())
    }
}
