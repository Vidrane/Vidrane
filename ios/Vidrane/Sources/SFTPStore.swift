import Foundation
import NIOSSH
import Security
import SwiftUI

struct SFTPServer: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var host: String
    var port: Int
    var username: String
    var rootPath: String
    /// Full OpenSSH public key (not a secret); pinned before first connection.
    var trustedHostKey: String
}

enum SFTPError: LocalizedError {
    case invalidServer
    case invalidPath
    case invalidHostKey
    case missingPassword
    case escapedRoot
    case unsupportedEntry
    case incompleteTransfer

    var errorDescription: String? {
        switch self {
        case .invalidServer: return "Укажите корректный хост, порт и имя пользователя."
        case .invalidPath: return "Используйте абсолютный SFTP-путь без .. или ."
        case .invalidHostKey:
            return "Нужен проверенный публичный ключ SSH-сервера в формате OpenSSH."
        case .missingPassword: return "Пароль SFTP отсутствует в Keychain."
        case .escapedRoot: return "SFTP-путь выходит за пределы выбранной папки."
        case .unsupportedEntry: return "Символические ссылки и неизвестные типы файлов пока не поддерживаются."
        case .incompleteTransfer: return "SFTP-сервер неожиданно завершил передачу файла."
        }
    }
}

enum SFTPPathPolicy {
    static func normalize(_ path: String) throws -> String {
        guard path.hasPrefix("/"),
              !path.contains("\\"),
              !path.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) else { throw SFTPError.invalidPath }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard !parts.contains(where: { $0 == "." || $0 == ".." }) else {
            throw SFTPError.invalidPath
        }
        return parts.isEmpty ? "/" : "/" + parts.joined(separator: "/")
    }

    static func inside(_ candidate: String, root: String) -> Bool {
        root == "/" ? candidate.hasPrefix("/") :
            candidate == root || candidate.hasPrefix(root + "/")
    }

    static func child(_ name: String, in directory: String, root: String) throws -> String {
        guard !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains("\\"),
              !name.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) else { throw SFTPError.invalidPath }
        let candidate = try normalize(directory == "/" ? "/" + name : directory + "/" + name)
        guard inside(candidate, root: root) else { throw SFTPError.escapedRoot }
        return candidate
    }
}

@MainActor
final class SFTPStore: ObservableObject {
    static let shared = SFTPStore()

    @Published private(set) var servers: [SFTPServer] = []
    private let defaultsKey = "vidrane.sftp.servers.v1"
    private let credentialService = "org.vidrane.sftp"

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([SFTPServer].self, from: data) {
            servers = saved
        }
    }

    func add(title: String, host rawHost: String, port: Int,
             username rawUsername: String, password: String,
             rootPath: String, trustedHostKey rawKey: String) throws {
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = rawUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        guard !host.isEmpty, host.unicodeScalars.allSatisfy(allowed.contains),
              !host.hasPrefix("-"), !host.hasSuffix("-"),
              !username.isEmpty, !username.contains("\n"),
              (1...65535).contains(port) else { throw SFTPError.invalidServer }
        let root = try SFTPPathPolicy.normalize(rootPath)
        let trustedHostKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trustedHostKey.contains("\n"), !trustedHostKey.contains("\r"),
              (try? NIOSSHPublicKey(openSSHPublicKey: trustedHostKey)) != nil else {
            throw SFTPError.invalidHostKey
        }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let server = SFTPServer(
            id: UUID(), title: title.isEmpty ? host : title,
            host: host, port: port, username: username,
            rootPath: root, trustedHostKey: trustedHostKey
        )
        try savePassword(password, for: server.id)
        servers.append(server)
        persist()
    }

    func password(for server: SFTPServer) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: credentialService,
            kSecAttrAccount as String: server.id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw SFTPError.missingPassword
        }
        return password
    }

    func remove(_ server: SFTPServer) {
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
        if let data = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func savePassword(_ value: String, for id: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: credentialService,
            kSecAttrAccount as String: id.uuidString,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: Data(value.utf8)
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(
                domain: NSOSStatusErrorDomain, code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Не удалось сохранить SFTP-пароль в Keychain."]
            )
        }
    }
}
