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
    /// Separate Keychain account holding the per-install random key for the UserDefaults fallback.
    private static let fallbackKeyAccount = "fallback-encryption-key"

    private static var serviceName: String {
        Bundle.main.bundleIdentifier ?? "com.localserverwrapper.unknown"
    }

    // MARK: - Public API

    /// Persist credentials. Returns `false` when secure storage is impossible (neither the
    /// Keychain item nor a Keychain-held encryption key could be written) — in that case nothing
    /// is written in a guessable form and the caller should tell the user (TASK-7).
    @discardableResult
    static func save(_ credentials: [Credential]) -> Bool {
        guard let data = try? JSONEncoder().encode(credentials) else {
            os_log(.error, log: logger, "Failed to encode credentials")
            return false
        }

        if saveToKeychain(data) {
            UserDefaults.standard.removeObject(forKey: accountName)
            return true
        }

        // Keychain item write failed. Fall back to encrypted UserDefaults — but only under a
        // per-install random key held in the Keychain, never a key derivable from the public
        // bundle identifier. If we can't get that key, refuse to persist (no guessable fallback).
        guard let key = getOrCreateFallbackKey(), let encrypted = encrypt(data, using: key) else {
            os_log(.error, log: logger, "Secure storage unavailable, credentials NOT persisted")
            return false
        }

        UserDefaults.standard.set(encrypted, forKey: accountName)
        os_log(.info, log: logger, "Credentials saved to encrypted UserDefaults fallback (per-install key)")
        return true
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

        // Current format: AES-GCM under the per-install random key.
        if let key = loadFallbackKey(),
           let decrypted = decrypt(stored, using: key),
           let credentials = try? JSONDecoder().decode([Credential].self, from: decrypted) {
            os_log(.info, log: logger, "Loaded %d credentials from encrypted UserDefaults", credentials.count)
            return credentials
        }

        // Legacy format: AES-GCM under the old SHA256(bundleID) key. Decode so we can migrate;
        // load() re-saves immediately, re-encrypting under the per-install key (TASK-7 migration).
        if let decrypted = decryptLegacy(stored),
           let credentials = try? JSONDecoder().decode([Credential].self, from: decrypted) {
            os_log(.info, log: logger, "Loaded %d credentials from legacy-key UserDefaults, will migrate", credentials.count)
            return credentials
        }

        // Plaintext (oldest format, from before encryption was added).
        if let credentials = try? JSONDecoder().decode([Credential].self, from: stored) {
            os_log(.info, log: logger, "Loaded %d credentials from legacy plaintext UserDefaults, will migrate", credentials.count)
            return credentials
        }

        return nil
    }

    // MARK: - Per-install fallback key (TASK-7)

    /// Read-or-create the random fallback key in the Keychain. Returns nil if it can't be
    /// retrieved or stored (in which case we must not persist under a guessable key).
    private static func getOrCreateFallbackKey() -> SymmetricKey? {
        if let existing = loadFallbackKey() { return existing }

        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: fallbackKeyAccount,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            os_log(.error, log: logger, "Failed to store fallback encryption key: %d", status)
            return nil
        }
        return key
    }

    /// Read the fallback key from the Keychain without creating one.
    private static func loadFallbackKey() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: fallbackKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return SymmetricKey(data: data)
    }

    // MARK: - Crypto

    private static func encrypt(_ data: Data, using key: SymmetricKey) -> Data? {
        do {
            let sealed = try AES.GCM.seal(data, using: key)
            return sealed.combined
        } catch {
            os_log(.error, log: logger, "AES-GCM encryption failed: %{public}@", error.localizedDescription)
            return nil
        }
    }

    private static func decrypt(_ data: Data, using key: SymmetricKey) -> Data? {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            return nil
        }
    }

    /// Decrypt data written by the old, insecure key derived from the public bundle identifier.
    /// Used only to migrate existing data to the per-install key; not used for new writes.
    private static func decryptLegacy(_ data: Data) -> Data? {
        let legacyKey = SymmetricKey(data: SHA256.hash(data: Data(serviceName.utf8)))
        return decrypt(data, using: legacyKey)
    }
}
