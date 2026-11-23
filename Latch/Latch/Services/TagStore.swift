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

    /// Returns nil when the Keychain could not be read (as opposed to
    /// holding no tags), so callers do not mistake a failed read for
    /// "nothing paired" and wipe what they already have in memory.
    static func loadTags() -> [PairedTag]? {
        switch read(tagsKey) {
        case .missing:
            return []
        case .failed:
            return nil
        case .found(let data):
            return try? JSONDecoder().decode([PairedTag].self, from: data)
        }
    }

    /// Returns false if the tags could not be saved.
    static func saveTags(_ tags: [PairedTag]) -> Bool {
        guard let data = try? JSONEncoder().encode(tags) else { return false }
        return write(tagsKey, data)
    }

    /// Returns nil when the Keychain could not be read.
    static func emergencyUsed() -> Int? {
        switch read(emergencyKey) {
        case .missing:
            return 0
        case .failed:
            return nil
        case .found(let data):
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            return Int(text)
        }
    }

    /// Returns false if the counter could not be saved.
    @discardableResult
    static func setEmergencyUsed(_ value: Int) -> Bool {
        write(emergencyKey, Data(String(value).utf8))
    }

    // MARK: Keychain

    private enum ReadResult {
        case found(Data)
        case missing
        case failed(OSStatus)
    }

    private static func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    private static func read(_ key: String) -> ReadResult {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return .failed(status) }
            return .found(data)
        case errSecItemNotFound:
            return .missing
        default:
            return .failed(status)
        }
    }

    private static func write(_ key: String, _ data: Data) -> Bool {
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery(key) as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var add = baseQuery(key)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}
