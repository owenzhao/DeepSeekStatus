import Foundation
import Security

/// 用户 API Key 的安全存储。
///
/// 存进 macOS 钥匙串（Keychain），而不是 `UserDefaults`：
/// 钥匙串条目由系统用登录钥匙串的主密钥加密后落盘，只有签名匹配的 App 才读得到；
/// `UserDefaults` 是明文 plist，任何能读用户目录的进程都能直接把 Key 拷走。
///
/// 也刻意**不**在钥匙串之上再套一层自己写的加密：解密用的那把密钥最终还是要存进
/// 同一个钥匙串，安全强度没有提升，只会让代码更复杂、更容易写错。
enum APIKeyStore {

    /// 钥匙串条目的 service / account。service 带上 bundle id，避免和其它 App 撞名。
    private static let service = "com.parussoft.DeepSeekStatus.deepseek"
    private static let account = "api-key"

    /// 读取已保存的 Key；没保存过（或内容为空）时返回 `nil`。
    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            return nil
        }
        return key
    }

    /// 保存 Key（已经存在则覆盖）。
    @discardableResult
    static func save(_ key: String) -> Result<Void, APIKeyError> {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(trimmed.utf8),
            // 第一次解锁之后就可读：开机自启的菜单栏 App 登录进来就能自动刷新余额。
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        // 先试更新，不存在再新增 —— 这样「换 Key」不会留下多余条目。
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return .success(()) }
        guard updateStatus == errSecItemNotFound else { return .failure(.keychain(updateStatus)) }

        var addQuery = query
        addQuery.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        return addStatus == errSecSuccess ? .success(()) : .failure(.keychain(addStatus))
    }

    /// 删除已保存的 Key。没保存过时也视为成功。
    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// 校验 / 保存 API Key 时的错误。
enum APIKeyError: LocalizedError {
    /// 输入为空。
    case empty
    /// 钥匙串操作失败。
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .empty:
            return String(localized: "balance.key.empty",
                          defaultValue: "Please enter an API key.")
        case .keychain(let status):
            let reason = SecCopyErrorMessageString(status, nil).map { $0 as String } ?? "OSStatus \(status)"
            return String(format: String(localized: "balance.key.saveFailed",
                                        defaultValue: "Couldn’t save the API key: %@"),
                          reason)
        }
    }
}
