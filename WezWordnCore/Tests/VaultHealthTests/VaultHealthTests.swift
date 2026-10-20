import XCTest
@testable import VaultHealth

final class VaultHealthTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    private func item(_ id: String, domain: String = "example.com", username: String? = "user",
                      email: String? = "user@example.com", password: String,
                      ageDays: Double = 10, totp: Bool = true) -> VaultHealthItem {
        VaultHealthItem(id: id, domain: domain, username: username, email: email, password: password,
                        updatedAt: now.addingTimeInterval(-ageDays * 86400), hasTOTP: totp)
    }
    // Strong synthetic password: 20 chars, mixed classes, not common.
    let strong = "X9$kQ2!mZp7#LwR4&vN8"

    func testWeakDetection() {
        let report = VaultHealth.analyze(items: [item("a", password: "short")], now: now)
        XCTAssertEqual(report.weakCount, 1)
        // A >=12-char single-class password is weak via entropy (<45 bits).
        let report2 = VaultHealth.analyze(items: [item("b", password: "aaaaaaaaaaaaaa")], now: now)
        XCTAssertEqual(report2.weakCount, 1)
        let ok = VaultHealth.analyze(items: [item("c", password: strong)], now: now)
        XCTAssertEqual(ok.weakCount, 0)
        XCTAssertTrue(VaultHealth.isWeak("password")) // common list, also short
    }
    func testReusedDetection() {
        let items = [item("a", password: strong), item("b", domain: "other.com", username: "u2", password: strong),
                     item("c", domain: "third.com", username: "u3", password: strong + "Zz9!")]
        let report = VaultHealth.analyze(items: items, now: now)
        XCTAssertEqual(report.reusedCount, 2)
    }
    func testOldDetection() {
        let report = VaultHealth.analyze(items: [item("a", password: strong, ageDays: 400), item("b", password: strong + "Aa1!", ageDays: 10)], now: now)
        XCTAssertEqual(report.oldCount, 1)
    }
    func testDuplicateAccountDetection() {
        let items = [item("a", password: strong), item("b", password: strong + "Aa1!")] // same domain+username
        let report = VaultHealth.analyze(items: items, now: now)
        XCTAssertEqual(report.duplicateAccountCount, 2)
    }
    func testMissingTOTPAndIdentity() {
        let report = VaultHealth.analyze(items: [item("a", username: nil, email: nil, password: strong, totp: false)], now: now)
        XCTAssertEqual(report.missingTOTPCount, 1)
        XCTAssertEqual(report.missingIdentityCount, 1)
    }
    func testScorePerfectAndWorst() {
        let perfect = VaultHealth.analyze(items: [item("a", password: strong), item("b", domain: "x.com", username: "u9", password: strong + "Qq7!")], now: now)
        XCTAssertEqual(perfect.score, 100)
        XCTAssertEqual(perfect.highRiskCount, 0)
        // Single weak, reused-not-possible, no TOTP, old, missing identity:
        // deductions 30 (weak) + 20 (totp) + 15 (old) = 65 -> score 35.
        let bad = VaultHealth.analyze(items: [item("a", username: nil, email: nil, password: "short", ageDays: 900, totp: false)], now: now)
        XCTAssertEqual(bad.score, 35)
        // Empty vault: documented score 100, all zero.
        let empty = VaultHealth.analyze(items: [], now: now)
        XCTAssertEqual(empty.score, 100); XCTAssertEqual(empty.totalCount, 0)
    }
    func testHighRiskWeakPlusReused() {
        let items = [item("a", password: "short"), item("b", domain: "o.com", username: "u2", password: "short")]
        let report = VaultHealth.analyze(items: items, now: now)
        XCTAssertEqual(report.highRiskCount, 2)
    }
}
