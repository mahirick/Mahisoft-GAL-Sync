import XCTest
@testable import DirectorySync

final class SyncAccountTests: XCTestCase {

    func testAccountCreation() {
        let account = SyncAccount(email: "rick@mahisoft.com")

        XCTAssertEqual(account.email, "rick@mahisoft.com")
        XCTAssertEqual(account.domain, "mahisoft.com")
        XCTAssertFalse(account.isAdmin)
        XCTAssertNil(account.lastSyncDate)
        XCTAssertEqual(account.lastSyncStatus, .never)
        XCTAssertFalse(account.needsReauth)
    }

    func testAccountDomainExtraction() {
        let account1 = SyncAccount(email: "user@h3y.com")
        XCTAssertEqual(account1.domain, "h3y.com")

        let account2 = SyncAccount(email: "user@sub.domain.com")
        XCTAssertEqual(account2.domain, "sub.domain.com")
    }

    func testAccountCodable() throws {
        let original = SyncAccount(email: "test@example.com")

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SyncAccount.self, from: data)

        XCTAssertEqual(original.id, decoded.id)
        XCTAssertEqual(original.email, decoded.email)
        XCTAssertEqual(original.domain, decoded.domain)
        XCTAssertEqual(original.isAdmin, decoded.isAdmin)
        XCTAssertEqual(original.lastSyncStatus, decoded.lastSyncStatus)
    }
}
