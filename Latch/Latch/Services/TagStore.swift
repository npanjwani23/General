import Foundation
import Security

struct PairedTag: Codable, Identifiable, Equatable {
    /// Factory UID of the NFC tag, uppercase hex.
    let id: String
    var name: String
}

/// Paired tags and the emergency unlock counter live in the Keychain,
/// which outlasts deleting and reinstalling the app. That keeps the
/// emergency counter from being reset by a reinstall.
enum TagStore {
    static let emergencyLimit = 5

    private static let service = "app.latch.personal"
    private static let tagsKey = "pairedTags"
    private static let emergencyKey = "emergencyUsed"

    static func loadTags() -> [PairedTag] {
        guard let data = read(tagsKey),
              let tags = try? JSONDecoder().decode([PairedTag].self, from: data) else {
            return []
        }
        return tags
    }

    static func saveTags(_ tags: [PairedTag]) {
        if let data = try? JSONEncoder().encode(tags) {
            write(tagsKey, data)
        }
    }

    static func emergencyUsed() -> Int {
        guard let data = read(emergencyKey),
              let text = String(data: data, encoding: .utf8),
              let value = Int(text) else {
            return 0
        }
        return value
    }

    static func setEmergencyUsed(_ value: Int) {
        write(emergencyKey, Data(String(value).utf8))
    }

    // MARK: Keychain

    private static func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    private static func read(_ key: String) -> Data? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    private static func write(_ key: String, _ data: Data) {
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery(key) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery(key)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
