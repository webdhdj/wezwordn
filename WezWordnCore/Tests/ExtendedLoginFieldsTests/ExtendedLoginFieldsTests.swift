import XCTest
@testable import ExtendedLoginFields

final class ExtendedLoginFieldsTests: XCTestCase {
    func testSeparateFieldsRoundtripCodable() throws {
        let item = ExtendedLogin(username: "wesam", email: "wesam@example.com", password: "s3cret!")
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ExtendedLogin.self, from: data)
        XCTAssertEqual(decoded, item)
        XCTAssertNotEqual(decoded.username, decoded.email)
    }
    func testMigrationEmailShapedUsernameCopiesAndKeepsUsername() {
        let migrated = ExtendedLogin.migrate(legacy: LegacyLogin(username: "user@example.com", password: "pw"))
        XCTAssertEqual(migrated.email, "user@example.com")
        XCTAssertEqual(migrated.username, "user@example.com") // kept for AutoFill compatibility
        XCTAssertEqual(migrated.password, "pw")
    }
    func testMigrationNonEmailUsernameLeavesEmailNil() {
        let migrated = ExtendedLogin.migrate(legacy: LegacyLogin(username: "plainuser", password: "pw"))
        XCTAssertNil(migrated.email)
        XCTAssertEqual(migrated.username, "plainuser")
    }
    func testMatchesSearchesBothFieldsCaseInsensitively() {
        let item = ExtendedLogin(username: "Alice", email: "Bob@Example.com", password: "x")
        XCTAssertTrue(item.matches(search: "alice"))
        XCTAssertTrue(item.matches(search: "BOB@exam"))
        XCTAssertTrue(item.matches(search: ""))
        XCTAssertFalse(item.matches(search: "charlie"))
    }
    func testEmailValidation() {
        XCTAssertTrue(ExtendedLogin.isValidEmail("a.b+tag@sub.example.co"))
        XCTAssertFalse(ExtendedLogin.isValidEmail("not-an-email"))
        XCTAssertFalse(ExtendedLogin.isValidEmail("a@b"))
        XCTAssertFalse(ExtendedLogin.isValidEmail("a b@example.com"))
        XCTAssertFalse(ExtendedLogin.isValidEmail("@example.com"))
    }
}
