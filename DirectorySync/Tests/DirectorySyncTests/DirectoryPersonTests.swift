import XCTest
@testable import DirectorySync

final class DirectoryPersonTests: XCTestCase {

    // MARK: - Admin API Parsing

    func testParseFromAdminJSON_fullUser() {
        let json: [String: Any] = [
            "primaryEmail": "john@example.com",
            "suspended": false,
            "name": [
                "fullName": "John Doe",
                "givenName": "John",
                "familyName": "Doe"
            ],
            "emails": [
                ["address": "john@example.com", "primary": true],
                ["address": "john.doe@example.com"]
            ],
            "phones": [
                ["value": "+1234567890", "type": "work"],
                ["value": "+0987654321", "type": "mobile"]
            ],
            "organizations": [
                ["title": "Engineer", "department": "Engineering", "name": "Example Inc"]
            ],
            "orgUnitPath": "/Engineering",
            "thumbnailPhotoUrl": "https://example.com/photo.jpg"
        ]

        let person = DirectoryPerson(fromAdminJSON: json, domain: "example.com")

        XCTAssertNotNil(person)
        XCTAssertEqual(person?.id, "john@example.com")
        XCTAssertEqual(person?.fullName, "John Doe")
        XCTAssertEqual(person?.givenName, "John")
        XCTAssertEqual(person?.familyName, "Doe")
        XCTAssertEqual(person?.primaryEmail, "john@example.com")
        XCTAssertEqual(person?.emails.count, 2)
        XCTAssertEqual(person?.phoneNumbers.count, 2)
        XCTAssertEqual(person?.phoneNumbers.first?.type, "work")
        XCTAssertEqual(person?.jobTitle, "Engineer")
        XCTAssertEqual(person?.department, "Engineering")
        XCTAssertEqual(person?.organizationName, "Example Inc")
        XCTAssertEqual(person?.orgUnitPath, "/Engineering")
        XCTAssertEqual(person?.photoURL?.absoluteString, "https://example.com/photo.jpg")
        XCTAssertFalse(person?.isSuspended ?? true)
        XCTAssertEqual(person?.domain, "example.com")
    }

    func testParseFromAdminJSON_minimalUser() {
        let json: [String: Any] = [
            "primaryEmail": "jane@example.com"
        ]

        let person = DirectoryPerson(fromAdminJSON: json, domain: "example.com")

        XCTAssertNotNil(person)
        XCTAssertEqual(person?.primaryEmail, "jane@example.com")
        XCTAssertEqual(person?.fullName, "jane@example.com") // falls back to email
        XCTAssertEqual(person?.emails.count, 1)
        XCTAssertTrue(person?.phoneNumbers.isEmpty ?? false)
        XCTAssertNil(person?.jobTitle)
    }

    func testParseFromAdminJSON_missingEmail() {
        let json: [String: Any] = [
            "name": ["fullName": "No Email"]
        ]

        let person = DirectoryPerson(fromAdminJSON: json, domain: "example.com")
        XCTAssertNil(person)
    }

    func testParseFromAdminJSON_suspendedUser() {
        let json: [String: Any] = [
            "primaryEmail": "suspended@example.com",
            "suspended": true
        ]

        let person = DirectoryPerson(fromAdminJSON: json, domain: "example.com")
        XCTAssertTrue(person?.isSuspended ?? false)
    }

    // MARK: - People API Parsing

    func testParseFromPeopleJSON_fullPerson() {
        let json: [String: Any] = [
            "names": [
                ["displayName": "Jane Smith", "givenName": "Jane", "familyName": "Smith"]
            ],
            "emailAddresses": [
                ["value": "jane@example.com"],
                ["value": "j.smith@example.com"]
            ],
            "phoneNumbers": [
                ["value": "+1111111111", "type": "mobile"]
            ],
            "organizations": [
                ["title": "Manager", "department": "Sales", "name": "Example Inc"]
            ],
            "photos": [
                ["url": "https://example.com/jane.jpg"]
            ]
        ]

        let person = DirectoryPerson(fromPeopleJSON: json, domain: "example.com")

        XCTAssertNotNil(person)
        XCTAssertEqual(person?.fullName, "Jane Smith")
        XCTAssertEqual(person?.emails.count, 2)
        XCTAssertEqual(person?.phoneNumbers.count, 1)
        XCTAssertEqual(person?.jobTitle, "Manager")
        XCTAssertEqual(person?.photoURL?.absoluteString, "https://example.com/jane.jpg")
        XCTAssertFalse(person?.isSuspended ?? true) // People API doesn't expose suspended
    }

    func testParseFromPeopleJSON_missingName() {
        let json: [String: Any] = [
            "emailAddresses": [["value": "noname@example.com"]]
        ]

        let person = DirectoryPerson(fromPeopleJSON: json, domain: "example.com")
        XCTAssertNil(person) // name is required
    }

    // MARK: - Equatable

    func testEquality() {
        let json: [String: Any] = [
            "primaryEmail": "test@example.com",
            "name": ["fullName": "Test", "givenName": "Test", "familyName": "User"]
        ]

        let person1 = DirectoryPerson(fromAdminJSON: json, domain: "example.com")
        let person2 = DirectoryPerson(fromAdminJSON: json, domain: "example.com")

        XCTAssertEqual(person1, person2)
    }

    // MARK: - Display Domain

    func testDisplayDomain() {
        let json: [String: Any] = [
            "primaryEmail": "test@mahisoft.com",
            "name": ["fullName": "Test", "givenName": "Test", "familyName": "User"]
        ]

        let person = DirectoryPerson(fromAdminJSON: json, domain: "mahisoft.com")
        XCTAssertEqual(person?.displayDomain, "mahisoft")
    }
}
