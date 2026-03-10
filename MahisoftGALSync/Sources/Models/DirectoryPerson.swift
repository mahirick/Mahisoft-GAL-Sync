import Foundation

struct DirectoryPerson: Identifiable, Codable, Equatable {
    let id: String // unique key: email
    var fullName: String
    var givenName: String
    var familyName: String
    var primaryEmail: String
    var emails: [String]
    var phoneNumbers: [PhoneEntry]
    var jobTitle: String?
    var department: String?
    var organizationName: String?
    var orgUnitPath: String?
    var photoURL: URL?
    var isSuspended: Bool
    var domain: String

    struct PhoneEntry: Codable, Equatable {
        let value: String
        let type: String? // "work", "mobile", "home"
    }

    var displayDomain: String {
        domain.split(separator: ".").first.map(String.init) ?? domain
    }
}

// MARK: - Parsing from Google Admin Directory API

extension DirectoryPerson {
    init?(fromAdminJSON json: [String: Any], domain: String) {
        guard let primaryEmail = json["primaryEmail"] as? String else { return nil }

        self.id = primaryEmail.lowercased()
        self.primaryEmail = primaryEmail
        self.domain = domain
        self.isSuspended = json["suspended"] as? Bool ?? false

        let name = json["name"] as? [String: Any]
        self.fullName = name?["fullName"] as? String ?? primaryEmail
        self.givenName = name?["givenName"] as? String ?? ""
        self.familyName = name?["familyName"] as? String ?? ""

        // Emails
        var parsedEmails: [String] = [primaryEmail]
        if let emailArray = json["emails"] as? [[String: Any]] {
            for entry in emailArray {
                if let addr = entry["address"] as? String, addr != primaryEmail {
                    parsedEmails.append(addr)
                }
            }
        }
        self.emails = parsedEmails

        // Phones
        var parsedPhones: [PhoneEntry] = []
        if let phoneArray = json["phones"] as? [[String: Any]] {
            for entry in phoneArray {
                if let value = entry["value"] as? String {
                    parsedPhones.append(PhoneEntry(value: value, type: entry["type"] as? String))
                }
            }
        }
        self.phoneNumbers = parsedPhones

        // Organization
        if let orgs = json["organizations"] as? [[String: Any]], let org = orgs.first {
            self.jobTitle = org["title"] as? String
            self.department = org["department"] as? String
            self.organizationName = org["name"] as? String
        } else {
            self.jobTitle = nil
            self.department = nil
            self.organizationName = nil
        }

        self.orgUnitPath = json["orgUnitPath"] as? String

        // Photo
        if let photoData = json["thumbnailPhotoUrl"] as? String {
            self.photoURL = URL(string: photoData)
        } else {
            self.photoURL = nil
        }
    }
}

// MARK: - Parsing from Google People API (Directory)

extension DirectoryPerson {
    init?(fromPeopleJSON json: [String: Any], domain: String) {
        // Names
        guard let names = json["names"] as? [[String: Any]], let name = names.first else { return nil }
        self.givenName = name["givenName"] as? String ?? ""
        self.familyName = name["familyName"] as? String ?? ""
        self.fullName = name["displayName"] as? String ?? "\(givenName) \(familyName)"

        // Emails
        guard let emailAddresses = json["emailAddresses"] as? [[String: Any]],
              let primaryEmailEntry = emailAddresses.first,
              let primaryEmail = primaryEmailEntry["value"] as? String else { return nil }

        self.id = primaryEmail.lowercased()
        self.primaryEmail = primaryEmail
        self.domain = domain
        self.isSuspended = false

        self.emails = emailAddresses.compactMap { $0["value"] as? String }

        // Phones
        if let phoneArray = json["phoneNumbers"] as? [[String: Any]] {
            self.phoneNumbers = phoneArray.compactMap { entry in
                guard let value = entry["value"] as? String else { return nil }
                return PhoneEntry(value: value, type: entry["type"] as? String)
            }
        } else {
            self.phoneNumbers = []
        }

        // Organization
        if let orgs = json["organizations"] as? [[String: Any]], let org = orgs.first {
            self.jobTitle = org["title"] as? String
            self.department = org["department"] as? String
            self.organizationName = org["name"] as? String
        } else {
            self.jobTitle = nil
            self.department = nil
            self.organizationName = nil
        }

        self.orgUnitPath = nil

        // Photo
        if let photos = json["photos"] as? [[String: Any]], let photo = photos.first,
           let url = photo["url"] as? String {
            self.photoURL = URL(string: url)
        } else {
            self.photoURL = nil
        }
    }
}
