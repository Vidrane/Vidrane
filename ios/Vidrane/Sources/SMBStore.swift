import Foundation
import Security
import SwiftUI

struct SMBServer: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let host: String
    let port: Int
    let share: String
    let domain: String
    let username: String
    let root: String
    /// SMB3 encryption is REQUIRED; no SMB1 or plaintext downgrade.
    let encrypted: Bool
}

enum SMBError: LocalizedError {
    case invalidConnection
    case invalidPath
    case missingPassword
    case unsupported
    case truncated
    case outsideShare

    var errorDescription: String? {
        switch self {
        case .invalidConnection: return "Укажите корректный SMB-хост, общую папку и пользователя."
        case .invalidPath: return "Неверный путь внутри SMB-ресурса."
        case .missingPassword: return "Не удалось получить пароль SMB из Keychain."
        case .unsupported: return "Тип файла или протокол SMB-сервера не поддерживается."
        case .truncated: return "SMB-сервер вернул неполный фрагмент файла."
        case .outsideShare: return "Путь выходит за пределы выбранного SMB-каталога."
        }
    }
}

enum SMBPath {
    static func normalized(_ input: String) throws -> String {
        let value = input.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if value.isEmpty { return "" }
        let segments = value.split(separator: "/", omittingEmptySubsequences: false)
        guard !segments.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
              !value.contains("\\"),
              !value.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) else { throw SMBError.invalidPath }
        return segments.joined(separator: "/")
    }

    static func allowed(_ path: String, root: String) -> Bool {
        root.isEmpty || path == root || path.hasPrefix(root + "/")
    }

    static func child(_ name: String, directory: String, root: String) throws -> String {
        guard !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains("\\"),
              !name.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) else { throw SMBError.invalidPath }
        let result = try normalized(directory.isEmpty ? name : directory + "/" + name)
        guard allowed(result, root: root) else { throw SMBError.outsideShare }
        return result
    }
}

@MainActor
final class SMBStore: ObservableObject {
    static let shared = SMBStore()
    @Published private(set) var servers: [SMBServer] = []

    private let defaultsKey = "vidrane.smb.servers.v1"
    private let credentialService = "org.vidrane.smb"

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let value = try? JSONDecoder().decode([SMBServer].self, from: data) {
            servers = value
        }
    }

    func add(
        title: String, host rawHost: String, port: Int, share: String,
        domain: String, username: String, password: String, root: String
    ) throws {
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let share = share.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let hostCharacters = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.:-")
        guard !host.isEmpty, host.unicodeScalars.allSatisfy(hostCharacters.contains),
              !share.isEmpty, share != ".", share != "..",
              !share.contains("/"), !share.contains("\\"),
              !username.isEmpty, !username.contains("\n"),
              (1...65535).contains(port), !domain.contains("\n")
        else { throw SMBError.invalidConnection }

        let value = SMBServer(
            id: UUID(), title: title.isEmpty ? share : title,
            host: host, port: port, share: share,
            domain: domain, username: username,
            root: try SMBPath.normalized(root), encrypted: true
        )
        try saveSecret(password, id: value.id)
        servers.append(value)
        persist()
    }

    func password(for server: SMBServer) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: credentialService,
            kSecAttrAccount as String: server.id.uuidString,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw SMBError.missingPassword
        }
        return password
    }

    func remove(_ server: SMBServer) {
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

    private func saveSecret(_ password: String, id: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: credentialService,
            kSecAttrAccount as String: id.uuidString,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: Data(password.utf8)
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(
                domain: NSOSStatusErrorDomain, code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Keychain не сохранил SMB-пароль."]
            )
        }
    }
}
