import Foundation
import Security

/// The SIS username/password, only if he chooses "احفظ على جوالي". Stays in this iPhone's Keychain.
enum Keychain {
    private static let service = "com.baihas.yarmoukstudent.sis"

    static func save(username: String, password: String) {
        delete()
        let data = try? JSONEncoder().encode([username, password])
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "sis",
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data ?? Data()
        ]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func load() -> (username: String, password: String)? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "sis",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let pair = try? JSONDecoder().decode([String].self, from: data), pair.count == 2 else { return nil }
        return (pair[0], pair[1])
    }

    static func delete() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(q as CFDictionary)
    }
}
