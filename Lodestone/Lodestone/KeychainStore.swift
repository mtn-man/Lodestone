//
//  KeychainStore.swift
//  Lodestone
//
//  Stores the Transmission auth credential (user:pass) in the macOS
//  Keychain rather than plaintext UserDefaults, since it's a real
//  credential rather than a preference.
//

import Foundation
import Security

enum KeychainStore {
    private static let service = "com.mtn-man.Lodestone.transmission-auth"
    private static let account = "transmission_auth"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func save(_ value: String) {
        SecItemDelete(baseQuery as CFDictionary)
        guard !value.isEmpty else { return }
        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load() -> String {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
