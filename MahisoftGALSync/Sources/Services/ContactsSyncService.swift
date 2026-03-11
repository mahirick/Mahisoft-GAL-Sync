import Foundation
import Contacts
import os

actor ContactsSyncService {
    static let shared = ContactsSyncService()

    private let store = CNContactStore()

    private init() {}

    // MARK: - Authorization

    func requestAccess() async throws -> Bool {
        do {
            return try await store.requestAccess(for: .contacts)
        } catch {
            Logger.contacts.error("Contacts access request failed: \(error.localizedDescription)")
            throw MahisoftGALSyncError.contactsAccessDenied
        }
    }

    func checkAccess() -> CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    // MARK: - Sync

    struct SyncResult: Sendable {
        let added: Int
        let updated: Int
        let removed: Int
        let photoErrors: Int
        let total: Int

        var summary: String {
            "\(total) people — \(added) added, \(updated) updated, \(removed) removed"
                + (photoErrors > 0 ? ", \(photoErrors) photo errors" : "")
        }
    }

    func syncContacts(
        people: [DirectoryPerson],
        groupName: String,
        removeDeleted: Bool,
        includePhotos: Bool
    ) async throws -> SyncResult {
        let status = checkAccess()
        guard status == .authorized else {
            Logger.contacts.error("Contacts access not authorized (status: \(String(describing: status)))")
            throw MahisoftGALSyncError.contactsAccessDenied
        }

        let group: CNGroup
        do {
            group = try findOrCreateGroup(named: groupName)
        } catch {
            Logger.contacts.error("Failed to find/create group '\(groupName)': \(error.localizedDescription)")
            throw MahisoftGALSyncError.contactsWriteFailed(error)
        }

        // Fetch group members for removal tracking only.
        // Note: predicateForContactsInGroup is unreliable with iCloud containers and may
        // return empty results. We do NOT use this for the create-vs-update decision.
        let groupContacts = (try? fetchContactsInGroup(group)) ?? []
        var groupEmailToContact: [String: CNContact] = [:]
        for contact in groupContacts {
            for email in contact.emailAddresses {
                groupEmailToContact[(email.value as String).lowercased()] = contact
            }
        }

        let directoryEmails = Set(people.map { $0.primaryEmail.lowercased() })

        var added = 0
        var updated = 0
        var removed = 0
        var photoErrors = 0

        // Add or update each person using a reliable store-wide email search.
        // This prevents duplicates when the group predicate returns stale/empty results.
        for person in people {
            let key = person.primaryEmail.lowercased()

            if let existing = try findContactByEmail(key) {
                do {
                    if try updateContact(existing, from: person, includePhotos: includePhotos) {
                        updated += 1
                    }
                } catch {
                    Logger.contacts.error("Failed to update contact \(person.primaryEmail): \(error.localizedDescription)")
                }
                // Ensure contact is in the group (handles post-reset re-add)
                if groupEmailToContact[key] == nil {
                    try? addContactToGroup(existing, group: group)
                }
            } else {
                do {
                    try await createContact(from: person, in: group, includePhotos: includePhotos, photoErrors: &photoErrors)
                    added += 1
                } catch {
                    Logger.contacts.error("Failed to create contact for \(person.primaryEmail): \(error.localizedDescription)")
                }
            }
        }

        // Remove group members no longer in the directory
        if removeDeleted {
            for (email, contact) in groupEmailToContact where !directoryEmails.contains(email) {
                do {
                    try removeContactFromGroup(contact, group: group)
                    removed += 1
                } catch {
                    Logger.contacts.error("Failed to remove \(email) from group: \(error.localizedDescription)")
                }
            }
        }

        let result = SyncResult(added: added, updated: updated, removed: removed, photoErrors: photoErrors, total: people.count)
        Logger.contacts.info("Sync complete for group '\(groupName)': \(result.summary)")
        return result
    }

    /// Searches the entire contact store by email — reliable across all containers
    /// (iCloud, On My Mac, Exchange, etc.), unlike predicateForContactsInGroup.
    private func findContactByEmail(_ email: String) throws -> CNContact? {
        let predicate = CNContact.predicateForContacts(matchingEmailAddress: email)
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactDepartmentNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactImageDataKey as CNKeyDescriptor,
            CNContactIdentifierKey as CNKeyDescriptor,
        ]
        return try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch).first
    }

    private func addContactToGroup(_ contact: CNContact, group: CNGroup) throws {
        guard let mutable = contact.mutableCopy() as? CNMutableContact else { return }
        let saveRequest = CNSaveRequest()
        saveRequest.addMember(mutable, to: group)
        try store.execute(saveRequest)
    }

    // MARK: - Group Management

    private func findOrCreateGroup(named name: String) throws -> CNGroup {
        let groups = try store.groups(matching: nil)
        if let existing = groups.first(where: { $0.name == name }) {
            return existing
        }

        let newGroup = CNMutableGroup()
        newGroup.name = name
        let saveRequest = CNSaveRequest()
        saveRequest.add(newGroup, toContainerWithIdentifier: nil)
        try store.execute(saveRequest)

        // Re-fetch to get the saved group with its identifier
        let updatedGroups = try store.groups(matching: nil)
        guard let created = updatedGroups.first(where: { $0.name == name }) else {
            throw MahisoftGALSyncError.contactsWriteFailed(
                NSError(domain: "ContactsSyncService", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Group '\(name)' was created but could not be re-fetched"])
            )
        }

        Logger.contacts.info("Created contact group: '\(name)'")
        return created
    }

    private func fetchContactsInGroup(_ group: CNGroup) throws -> [CNContact] {
        let predicate = CNContact.predicateForContactsInGroup(withIdentifier: group.identifier)
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactDepartmentNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactImageDataKey as CNKeyDescriptor,
            CNContactIdentifierKey as CNKeyDescriptor,
        ]
        return try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
    }

    // MARK: - Contact CRUD

    private func createContact(from person: DirectoryPerson, in group: CNGroup, includePhotos: Bool, photoErrors: inout Int) async throws {
        let contact = CNMutableContact()
        contact.givenName = person.givenName
        contact.familyName = person.familyName
        contact.emailAddresses = person.emails.map {
            CNLabeledValue(label: CNLabelWork, value: $0 as NSString)
        }
        contact.phoneNumbers = person.phoneNumbers.map {
            CNLabeledValue(label: phoneLabel(for: $0.type), value: CNPhoneNumber(stringValue: $0.value))
        }
        contact.jobTitle = person.jobTitle ?? ""
        contact.departmentName = person.department ?? ""
        contact.organizationName = person.organizationName ?? ""

        if includePhotos, let photoURL = person.photoURL {
            do {
                let data = try await downloadPhoto(from: photoURL)
                contact.imageData = data
            } catch {
                photoErrors += 1
                Logger.contacts.warning("Photo download failed for \(person.primaryEmail): \(error.localizedDescription)")
                // Continue without photo — non-fatal
            }
        }

        let saveRequest = CNSaveRequest()
        saveRequest.add(contact, toContainerWithIdentifier: nil)
        saveRequest.addMember(contact, to: group)
        try store.execute(saveRequest)
    }

    private func updateContact(_ existing: CNContact, from person: DirectoryPerson, includePhotos: Bool) throws -> Bool {
        guard let mutable = existing.mutableCopy() as? CNMutableContact else {
            Logger.contacts.warning("Could not create mutable copy for contact \(person.primaryEmail)")
            return false
        }

        var changed = false

        if mutable.givenName != person.givenName {
            mutable.givenName = person.givenName
            changed = true
        }
        if mutable.familyName != person.familyName {
            mutable.familyName = person.familyName
            changed = true
        }
        if mutable.jobTitle != (person.jobTitle ?? "") {
            mutable.jobTitle = person.jobTitle ?? ""
            changed = true
        }
        if mutable.departmentName != (person.department ?? "") {
            mutable.departmentName = person.department ?? ""
            changed = true
        }
        if mutable.organizationName != (person.organizationName ?? "") {
            mutable.organizationName = person.organizationName ?? ""
            changed = true
        }

        // Update emails — directory is source of truth
        let existingEmailValues = Set(mutable.emailAddresses.map { ($0.value as String).lowercased() })
        let newEmailValues = Set(person.emails.map { $0.lowercased() })
        if existingEmailValues != newEmailValues {
            mutable.emailAddresses = person.emails.map {
                CNLabeledValue(label: CNLabelWork, value: $0 as NSString)
            }
            changed = true
        }

        // Update phones — directory is source of truth
        let existingPhoneValues = Set(mutable.phoneNumbers.map { $0.value.stringValue })
        let newPhoneValues = Set(person.phoneNumbers.map { $0.value })
        if existingPhoneValues != newPhoneValues {
            mutable.phoneNumbers = person.phoneNumbers.map {
                CNLabeledValue(label: phoneLabel(for: $0.type), value: CNPhoneNumber(stringValue: $0.value))
            }
            changed = true
        }

        if changed {
            let saveRequest = CNSaveRequest()
            saveRequest.update(mutable)
            try store.execute(saveRequest)
        }

        return changed
    }

    private func removeContactFromGroup(_ contact: CNContact, group: CNGroup) throws {
        guard let mutable = contact.mutableCopy() as? CNMutableContact else {
            Logger.contacts.warning("Could not create mutable copy for removal")
            return
        }
        let saveRequest = CNSaveRequest()
        saveRequest.removeMember(mutable, from: group)
        try store.execute(saveRequest)
    }

    // MARK: - Helpers

    private func phoneLabel(for type: String?) -> String {
        switch type?.lowercased() {
        case "mobile": return CNLabelPhoneNumberMobile
        case "home": return CNLabelHome
        case "work": return CNLabelWork
        default: return CNLabelWork
        }
    }

    private func downloadPhoto(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw MahisoftGALSyncError.apiError(statusCode: httpResponse.statusCode, message: "Photo download returned \(httpResponse.statusCode)")
        }

        return data
    }

    // MARK: - Cleanup

    /// Deletes the named group entirely. Contacts that were members are NOT deleted —
    /// they lose group membership only. Used by Reset & Resync.
    func deleteGroup(named groupName: String) throws -> Bool {
        let groups = try store.groups(matching: nil)
        guard let group = groups.first(where: { $0.name == groupName }),
              let mutableGroup = group.mutableCopy() as? CNMutableGroup else {
            Logger.contacts.info("Group '\(groupName)' not found, nothing to delete")
            return false
        }
        let saveRequest = CNSaveRequest()
        saveRequest.delete(mutableGroup)
        try store.execute(saveRequest)
        Logger.contacts.info("Deleted contact group: '\(groupName)'")
        return true
    }

    func removeAllContactsInGroup(named groupName: String) throws -> Int {
        let groups = try store.groups(matching: nil)
        guard let group = groups.first(where: { $0.name == groupName }) else {
            Logger.contacts.info("Group '\(groupName)' not found, nothing to remove")
            return 0
        }

        let contacts = try fetchContactsInGroup(group)
        guard !contacts.isEmpty else { return 0 }

        let saveRequest = CNSaveRequest()
        for contact in contacts {
            if let mutable = contact.mutableCopy() as? CNMutableContact {
                saveRequest.removeMember(mutable, from: group)
            }
        }

        try store.execute(saveRequest)
        Logger.contacts.info("Removed \(contacts.count) contacts from group '\(groupName)'")
        return contacts.count
    }
}
