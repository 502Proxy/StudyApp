import Foundation
import Security

/// Speichert Server und Nutzername in `UserDefaults`, das Passwort im Schlüsselbund.
@MainActor
final class KeychainStudIPAccountStore: StudIPAccountStore {
    enum Key {
        static let server = "studip.server"
        static let username = "studip.username"
        static let autoSyncSlides = "studip.autoSyncSlides"
        static let lastSlideSync = "studip.lastSlideSync"
    }

    private static let service = "StudyApp Stud.IP"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var autoSyncSlides: Bool {
        get { defaults.object(forKey: Key.autoSyncSlides) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.autoSyncSlides) }
    }

    var lastSlideSync: Date? {
        get { defaults.object(forKey: Key.lastSlideSync) as? Date }
        set { defaults.set(newValue, forKey: Key.lastSlideSync) }
    }

    func load() -> StudIPCredentials? {
        guard let server = defaults.string(forKey: Key.server).flatMap(URL.init(string:)),
              let username = defaults.string(forKey: Key.username),
              let password = password(for: username) else { return nil }
        return StudIPCredentials(account: StudIPAccount(serverURL: server, username: username), password: password)
    }

    func save(_ credentials: StudIPCredentials) throws {
        if let previous = defaults.string(forKey: Key.username), previous != credentials.account.username {
            deletePassword(for: previous)
        }
        try storePassword(credentials.password, for: credentials.account.username)
        defaults.set(credentials.account.serverURL.absoluteString, forKey: Key.server)
        defaults.set(credentials.account.username, forKey: Key.username)
    }

    func delete() {
        if let username = defaults.string(forKey: Key.username) {
            deletePassword(for: username)
        }
        defaults.removeObject(forKey: Key.username)
        defaults.removeObject(forKey: Key.lastSlideSync)
    }

    // MARK: Schlüsselbund

    private func query(for username: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: username,
        ]
    }

    private func password(for username: String) -> String? {
        var query = query(for: username)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func storePassword(_ password: String, for username: String) throws {
        let data = Data(password.utf8)
        let status = SecItemUpdate(query(for: username) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(for: username)
            item[kSecValueData as String] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    private func deletePassword(for username: String) {
        SecItemDelete(query(for: username) as CFDictionary)
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "Code \(status)"
        return "Das Passwort konnte nicht im Schlüsselbund gespeichert werden: \(detail)"
    }
}
