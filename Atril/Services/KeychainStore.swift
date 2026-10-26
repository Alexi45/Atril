import Foundation
import Security

/// Guarda la clave de la API en el llavero del sistema (nunca en UserDefaults).
enum KeychainStore {
    private static let service = "com.alejandroriscart.atril"
    private static let account = "anthropic-api-key"

    static var apiKey: String {
        get {
            var query = baseQuery
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data else { return "" }
            return String(decoding: data, as: UTF8.self)
        }
        set {
            SecItemDelete(baseQuery as CFDictionary)
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(!trimmed.isEmpty, forKey: hasKeyFlag)
            guard !trimmed.isEmpty else { return }
            var query = baseQuery
            query[kSecValueData as String] = Data(trimmed.utf8)
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    static var hasKey: Bool { !apiKey.isEmpty }

    /// Copia en UserDefaults de si hay clave, para que las vistas reaccionen con `@AppStorage`.
    static let hasKeyFlag = "hasAPIKey"

    static func syncFlag() {
        UserDefaults.standard.set(hasKey, forKey: hasKeyFlag)
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
