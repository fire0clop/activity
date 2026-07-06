import Foundation
import Security

/// Безопасное хранение access/refresh токенов в Keychain.
final class TokenStore {
    private let service = "com.skhodka.app.tokens"
    private let accessKey = "access_token"
    private let refreshKey = "refresh_token"

    private(set) var accessToken: String?
    private(set) var refreshToken: String?

    init() {
        accessToken = read(accessKey)
        refreshToken = read(refreshKey)
    }

    var hasSession: Bool { accessToken != nil && refreshToken != nil }

    func save(access: String, refresh: String) {
        accessToken = access
        refreshToken = refresh
        write(accessKey, access)
        write(refreshKey, refresh)
    }

    func clear() {
        accessToken = nil
        refreshToken = nil
        delete(accessKey)
        delete(refreshKey)
    }

    // MARK: - Keychain

    private func write(_ key: String, _ value: String) {
        delete(key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
            // ThisDeviceOnly: токен не попадает в iCloud/iTunes-бэкап и не восстанавливается
            // на другом устройстве (refresh-токен живёт 30 дней — снижаем риск угона сессии).
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
