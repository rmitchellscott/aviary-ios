import Foundation
import WebKit
import Security

final class AuthManager {
    static let shared = AuthManager()

    private let serviceName = "io.scottlabs.aviary"
    private let cookieAccountKey = "auth_token"
    private var accessGroup: String {
        let teamID = Bundle.main.infoDictionary?["AppIdentifierPrefix"] as? String ?? ""
        return "\(teamID)group.io.scottlabs.aviary"
    }

    private init() {}

    var serverURL: String? {
        UserDefaults.standard.string(forKey: "server_url")?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func syncCookies(from webView: WKWebView) {
        guard let serverURL, let host = URL(string: serverURL)?.host else { return }

        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self else { return }
            for cookie in cookies where cookie.domain.contains(host) && cookie.name == "auth_token" {
                self.saveKeychain(account: self.cookieAccountKey, value: cookie.value)
                self.saveToAppGroup(key: "auth_token_cookie", value: cookie.value)
                return
            }
        }
    }

    func applyAuth(to request: inout URLRequest) {
        if let token = readKeychain(account: cookieAccountKey) ?? readFromAppGroup(key: "auth_token_cookie") {
            request.addValue("auth_token=\(token)", forHTTPHeaderField: "Cookie")
        }
    }

    // MARK: - Keychain helpers

    private func saveKeychain(account: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    private func readKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - App Group UserDefaults

    private var appGroupDefaults: UserDefaults? {
        UserDefaults(suiteName: "group.io.scottlabs.aviary")
    }

    private func saveToAppGroup(key: String, value: String) {
        appGroupDefaults?.set(value, forKey: key)
    }

    func readFromAppGroup(key: String) -> String? {
        appGroupDefaults?.string(forKey: key)
    }
}
