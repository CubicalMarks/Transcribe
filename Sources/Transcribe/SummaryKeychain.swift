import Foundation
import Security
import CryptoKit
import TranscribeCore

enum SummaryKeychain {
    private static func query(for settings: SummarySettings) throws -> [String: Any] {
        let endpoint = try settings.completionURL().absoluteString
        let account = SHA256.hash(data: Data(endpoint.utf8)).map { String(format: "%02x", $0) }.joined()
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "se.marcusliback.Transcribe.SummaryAPI",
                kSecAttrAccount as String: account]
    }

    static func read(_ settings: SummarySettings) throws -> String {
        var query = try query(for: settings)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw TranscribeError.message("Cannot read the summary API credential from Keychain (\(status)).")
        }
        return value
    }

    static func save(_ value: String, settings: SummarySettings) throws {
        let query = try query(for: settings)
        let data = Data(value.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        let status: OSStatus
        if data.isEmpty {
            status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw TranscribeError.message("Cannot remove the summary API credential from Keychain (\(status)).")
            }
            return
        }
        let updated = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        } else { status = updated }
        guard status == errSecSuccess else { throw TranscribeError.message("Cannot save the summary API credential in Keychain (\(status)).") }
    }
}
