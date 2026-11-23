import SwiftUI
import Foundation
import Security

@MainActor
final class WebDAVStore: ObservableObject {
    @Published private(set) var servers: [WebDAVServer] = []
    @Published var errorMessage: String?

    static let shared = WebDAVStore()
    private let defaultsKey = "vidrane.webdav.servers.v1"
    private let credentialService = "org.vidrane.webdav"

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let restored = try? JSONDecoder().decode([WebDAVServer].self, from: data) {
            servers = restored
        }
    }

    func add(title: String, address: String, username: String, password: String) throws {
        let root = try WebDAVURLPolicy.root(from: address)
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let server = WebDAVServer(
            id: UUID(),
            title: name.isEmpty ? (root.host ?? "WebDAV") : name,
            baseURL: root.absoluteString,
            username: username
        )
        if !username.isEmpty {
            try saveSecret(password, for: server.id)
        }
        servers.append(server)
        persist()
    }

    func access(_ server: WebDAVServer) throws -> WebDAVAccess {
        let password: String
        if server.username.isEmpty {
            password = ""
        } else {
            guard let secret = secret(for: server.id) else {
                throw WebDAVError.missingCredential
            }
            password = secret
        }
        return WebDAVAccess(server: server, password: password)
    }

    func remove(_ server: WebDAVServer) {
        servers.removeAll { $0.id == server.id }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: credentialService,
            kSecAttrAccount as String: server.id.uuidString
        ]
        SecItemDelete(query as CFDictionary)
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func saveSecret(_ secret: String, for id: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: credentialService,
            kSecAttrAccount as String: id.uuidString,
            kSecValueData as String: Data(secret.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Не удалось сохранить пароль в Keychain."])
        }
    }

    private func secret(for id: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: credentialService,
            kSecAttrAccount as String: id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
