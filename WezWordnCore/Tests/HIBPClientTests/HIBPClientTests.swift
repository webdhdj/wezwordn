import XCTest
@testable import HIBPClient

private struct MockTransport: HIBPTransport {
    var body: String
    // Reference box captures the prefixes the client actually sent.
    final class Box { var prefixes: [String] = [] }
    var box: Box? = nil
    func fetchRange(prefix: String) throws -> String {
        box?.prefixes.append(prefix)
        return body
    }
}

final class HIBPClientTests: XCTestCase {
    // Known vector: SHA1("password") = 5BAA61E4C9B93F3F0682250B6CF8331B7EE68FD8
    func testSHA1KnownVectorAndSplit() {
        let hex = HIBPClient.sha1Hex(of: "password")
        XCTAssertEqual(hex, "5BAA61E4C9B93F3F0682250B6CF8331B7EE68FD8")
        let (prefix, suffix) = HIBPClient.splitHash(hex)
        XCTAssertEqual(prefix, "5BAA6")
        XCTAssertEqual(suffix, "1E4C9B93F3F0682250B6CF8331B7EE68FD8")
        XCTAssertEqual(prefix.count, 5)
    }
    func testPwnedFoundWithKAnonymityOnly() throws {
        let box = MockTransport.Box()
        // Response contains the known suffix for "password" plus a decoy.
        let body = "0018A45C4D1DEF81644B54AB7F969B88D65:2\n1E4C9B93F3F0682250B6CF8331B7EE68FD8:9545824\n00C9ED1111B7D1111A1111111111111111111:3"
        let client = HIBPClient(transport: MockTransport(body: body, box: box))
        XCTAssertEqual(try client.pwnedCount(for: "password"), 9545824)
        XCTAssertTrue(try client.isPwned("password"))
        // Only the 5-char prefix ever reached the transport (two calls above:
        // pwnedCount + isPwned, hence two identical entries).
        XCTAssertEqual(box.prefixes, ["5BAA6", "5BAA6"])
    }
    func testNotPwnedReturnsZero() throws {
        let client = HIBPClient(transport: MockTransport(body: "0018A45C4D1DEF81644B54AB7F969B88D65:2"))
        XCTAssertEqual(try client.pwnedCount(for: "password"), 0)
        XCTAssertFalse(try client.isPwned("password"))
    }
    func testParserRejectsMalformed() {
        XCTAssertThrowsError(try HIBPClient.parseResponse("NOCOUNTLINE"))
        XCTAssertThrowsError(try HIBPClient.parseResponse("ABC:notanumber"))
        let ok = try! HIBPClient.parseResponse("ABC123:42\nDEF456:7")
        XCTAssertEqual(ok["ABC123"], 42); XCTAssertEqual(ok["DEF456"], 7)
    }
}
