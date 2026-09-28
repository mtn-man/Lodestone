//
//  KeychainStore.swift
//  Lodestone
//
//  Stores the Transmission auth credential (user:pass) in the macOS
//  Keychain rather than plaintext UserDefaults, since it's a real
//  credential rather than a preference.
//
//  Both operations report failure rather than absorbing it. A write that
//  silently does nothing produces a settings window that says "Saved."
//  and an app that then 401s on every add, with nothing connecting the
//  two; a read that silently returns "" is indistinguishable from "no
//  credential configured," which sends the user looking for the wrong
//  problem.
//

import Foundation
import Security

enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case loadFailed(OSStatus)
    case malformedData

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "could not save the transmission credential: \(Self.describe(status))"
        case .deleteFailed(let status):
            return "could not replace the saved transmission credential: \(Self.describe(status))"
        case .loadFailed(let status):
            return "could not read the saved transmission credential: \(Self.describe(status))"
        case .malformedData:
            return "the saved transmission credential is not readable text"
        }
    }

    private static func describe(_ status: OSStatus) -> String {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
    }
}

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

    /// Replaces the stored credential. An empty value clears it, which is a
    /// legitimate state -- Transmission allows unauthenticated RPC.
    ///
    /// Updates the existing item in place rather than deleting and
    /// re-adding: a failed `SecItemAdd` after a successful delete would
    /// otherwise leave no credential at all, silently losing a previously
    /// valid one. `SecItemUpdate` fails atomically, so a failure here
    /// leaves the old credential intact.
    static func save(_ value: String) throws {
        guard !value.isEmpty else {
            let deleteStatus = SecItemDelete(baseQuery as CFDictionary)
            guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
                throw KeychainError.deleteFailed(deleteStatus)
            }
            return
        }

        let newData: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, newData as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var attributes = baseQuery
            attributes[kSecValueData as String] = Data(value.utf8)
            let addStatus = SecItemAdd(attributes as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.saveFailed(addStatus)
            }
            return
        }
        guard updateStatus == errSecSuccess else {
            throw KeychainError.saveFailed(updateStatus)
        }
    }

    /// nil means no credential is configured. A read failure throws instead,
    /// so the two cannot be confused.
    static func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.loadFailed(status) }
        guard let data = result as? Data else { throw KeychainError.malformedData }
        guard let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.malformedData
        }
        return value
    }
}
