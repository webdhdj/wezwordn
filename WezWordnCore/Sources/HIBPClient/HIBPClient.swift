import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Crypto

/// Have I Been Pwned password check using k-anonymity only:
/// SHA1(password) is computed locally, only the first 5 hex characters are
/// sent to the range endpoint, and the returned suffix list is matched
/// locally. The full hash and the password itself never leave the device
/// through this client. Transport is injectable so tests run fully offline.
public protocol HIBPTransport {
    func fetchRange(prefix: String) throws -> String
}

public enum HIBPError: Error, Equatable {
    case malformedResponse(String)
}

public struct HIBPClient {
    public let transport: HIBPTransport
    public init(transport: HIBPTransport) { self.transport = transport }

    public static func sha1Hex(of password: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(password.utf8))
        return digest.map { String(format: "%02X", $0) }.joined()
    }

    public static func splitHash(_ hex: String) -> (prefix: String, suffix: String) {
        (String(hex.prefix(5)), String(hex.dropFirst(5)))
    }

    /// Parses a range response body: one `SUFFIX:count` per line.
    public static func parseResponse(_ body: String) throws -> [String: Int] {
        var out: [String: Int] = [:]
        for rawLine in body.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, let count = Int(parts[1].trimmingCharacters(in: .whitespaces)) else {
                throw HIBPError.malformedResponse(line)
            }
            out[parts[0].uppercased()] = count
        }
        return out
    }

    /// Returns the breach count for `password`, or 0 if its suffix is absent.
    public func pwnedCount(for password: String) throws -> Int {
        let hex = Self.sha1Hex(of: password)
        let (prefix, suffix) = Self.splitHash(hex)
        let body = try transport.fetchRange(prefix: prefix)
        let table = try Self.parseResponse(body)
        return table[suffix.uppercased()] ?? 0
    }

    public func isPwned(_ password: String) throws -> Bool {
        try pwnedCount(for: password) > 0
    }
}

/// Production transport hitting the real HIBP range API. Not used in tests.
public struct URLSessionHIBPTransport: HIBPTransport {
    public init() {}
    public func fetchRange(prefix: String) throws -> String {
        // Synchronous wrapper kept minimal; iOS app code should prefer an
        // async variant. Provided for completeness, excluded from tests.
        var result: Result<String, Error> = .failure(HIBPError.malformedResponse("no response"))
        let sem = DispatchSemaphore(value: 0)
        let url = URL(string: "https://api.pwnedpasswords.com/range/\(prefix)")!
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error { result = .failure(error) }
            else if let data, let s = String(data: data, encoding: .utf8) { result = .success(s) }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 15)
        return try result.get()
    }
}
