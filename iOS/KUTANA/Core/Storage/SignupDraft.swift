import Foundation
import Security

/// Registration details are held in the device Keychain until the verified account saves its profile.
/// Passwords and provider tokens are never stored in this draft.
struct LukaSignupDraft: Codable {
    let email: String
    let first_name: String
    let last_name: String
    let birth_date: String
    let phone_e164: String
    let phone_region: String
    let country_code: String
    let city: String
    let commune: String
    let share_location_with_recruiters: Bool
}

enum LukaSignupDraftStore {
    private static let account = "registration-profile-v1"
    private static let store = SecureTokenStore()

    static func backup() -> Data? { store.load(account: account) }
    static func save(_ draft: LukaSignupDraft) throws {
        var drafts = all()
        drafts.removeAll { $0.email.caseInsensitiveCompare(draft.email) == .orderedSame }
        drafts.append(draft)
        let data = try JSONEncoder().encode(drafts)
        guard store.save(data, account: account) == errSecSuccess else {
            throw LukaSignupDraftError.storageUnavailable
        }
    }
    static func restore(_ previous: Data?) {
        if let previous { _ = store.save(previous, account: account) }
        else { store.remove(account: account) }
    }
    static func load(for email: String) -> LukaSignupDraft? {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return all().first { $0.email.caseInsensitiveCompare(normalized) == .orderedSame }
    }
    static func remove(for email: String) {
        var drafts = all()
        let count = drafts.count
        drafts.removeAll { $0.email.caseInsensitiveCompare(email) == .orderedSame }
        guard drafts.count != count else { return }
        if drafts.isEmpty { store.remove(account: account) }
        else if let data = try? JSONEncoder().encode(drafts) { _ = store.save(data, account: account) }
    }
    private static func all() -> [LukaSignupDraft] {
        guard let data = store.load(account: account) else { return [] }
        return (try? JSONDecoder().decode([LukaSignupDraft].self, from: data)) ?? []
    }
}

enum LukaSignupDraftError: LocalizedError {
    case storageUnavailable
    var errorDescription: String? {
        "Impossible de conserver les informations d'inscription sur cet iPhone. Réessayez."
    }
}
