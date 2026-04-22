//
//  KeychainStorage.swift
//  SiteNote
//
//  iOS Keychain 的简单 String 读写封装。用于 OpenAI API Key 这种敏感数据。
//  UserDefaults 存 API key 很危险(备份/越狱可读),Keychain 是标准做法。
//

import Foundation
import Security

enum KeychainStorage {
    /// 所有条目共用的 service 前缀。
    private static let service = "com.banruo.SiteNote"

    /// 保存一段字符串。若同 key 已存在会覆盖。成功返回 true。
    @discardableResult
    static func save(_ value: String, for key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// 读取。不存在返回 nil。
    static func load(for key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    /// 删除一条。
    @discardableResult
    static func delete(for key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}

/// 固定的 Keychain key 名。
enum KeychainKeys {
    static let openAIAPIKey = "openai.apiKey"
}
