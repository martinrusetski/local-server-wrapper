//
//  KeychainManager.swift
//  ServerAppBundle
//

import Foundation
import Security
import CryptoKit
import os.log

private let logger = OSLog(subsystem: "com.localserverwrapper.serverappbundle", category: "keychain")

struct KeychainManager {
    private static let accountName = "saved-credentials"

    private static var serviceName: String {
        Bundle.main.bundleIdentifier ?? "com.localserverwrapper.unknown"
    }

    // MARK: - Public API

    static func save(_ credentials: [Credential]) {
        guard let data = try? JSONEncoder().encode(credentials) else {
            os_log(.error, log: logger, "Failed to encode credentials")
            return
        }

        if saveToKeychain(data) {
            UserDefaults.standard.removeObject(forKey: accountName)
            return
        }

        guard let encrypted = encrypt(data) else {
            os_log(.error, log: logger, "Both Keychain and encryption failed, credentials not persisted")
            return
        }

        UserDefaults.standard.set(encrypted, forKey: accountName)
        os_log(.info, log: logger, "Credentials saved to encrypted UserDefaults fallback")
    }

    static func load() -> [Credential] {
        if let credentials = loadFromKeychain() {
            return credentials
        }

        if let credentials = loadFromUserDefaults() {
            // Migration: found in UserDefaults, try to move to Keychain
            save(credentials)
            return credentials
        }

        os_log(.info, log: logger, "No saved credentials found")
        return []
    }

    static func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: accountName)
        os_log(.info, log: logger, "All credentials deleted")
    }

    // MARK: - Keychain

    private static func saveToKeychain(_ data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess {
            os_log(.info, log: logger, "Credentials updated in Keychain")
            return true
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess {
            os_log(.info, log: logger, "Credentials saved to Keychain")
            return true
        }

        os_log(.error, log: logger, "Keychain save failed: update=%d add=%d", updateStatus, addStatus)
        return false
    }

    private static func loadFromKeychain() -> [Credential]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }

        if let credentials = try? JSONDecoder().decode([Credential].self, from: data) {
            os_log(.info, log: logger, "Loaded %d credentials from Keychain", credentials.count)
            return credentials
        }

        return nil
    }

    // MARK: - AES-GCM Encrypted UserDefaults

    private static func loadFromUserDefaults() -> [Credential]? {
        guard let stored = UserDefaults.standard.data(forKey: accountName) else { return nil }

        // Try AES-GCM decryption first (current format)
        if let decrypted = decrypt(stored),
           let credentials = try? JSONDecoder().decode([Credential].self, from: decrypted) {
            os_log(.info, log: logger, "Loaded %d credentials from encrypted UserDefaults", credentials.count)
            return credentials
        }

        // Try plaintext (legacy format from before encryption was added)
        if let credentials = try? JSONDecoder().decode([Credential].self, from: stored) {
            os_log(.info, log: logger, "Loaded %d credentials from legacy UserDefaults, will migrate", credentials.count)
            return credentials
        }

        return nil
    }

    // MARK: - Crypto

    private static func encrypt(_ data: Data) -> Data? {
        let keyMaterial = SHA256.hash(data: Data(serviceName.utf8))
        let key = SymmetricKey(data: keyMaterial)
        do {
            let sealed = try AES.GCM.seal(data, using: key)
            return sealed.combined
        } catch {
            os_log(.error, log: logger, "AES-GCM encryption failed: %{public}@", error.localizedDescription)
            return nil
        }
    }

    private static func decrypt(_ data: Data) -> Data? {
        let keyMaterial = SHA256.hash(data: Data(serviceName.utf8))
        let key = SymmetricKey(data: keyMaterial)
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            return nil
        }
    }
}
