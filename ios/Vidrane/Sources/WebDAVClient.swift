import Foundation

struct WebDAVEntry: Identifiable, Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64?

    var id: String { url.absoluteString }
}

enum WebDAVError: LocalizedError {
    case invalidURL
    case forbiddenResponse
    case authenticationRequired
    case serverError(Int)
    case invalidResponse
    case missingCredential
    case unsupportedLocation
    case fileTooLarge
    case invalidName
    case rootMutation
    case targetExists

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Используйте HTTPS-адрес каталога WebDAV без логина и пароля в ссылке."
        case .forbiddenResponse: return "Сервер перенаправил запрос. Для безопасности автоматический переход отключён."
        case .authenticationRequired: return "Неверный логин/пароль или сервер требует авторизацию."
        case .serverError(let status): return "WebDAV вернул HTTP \(status)."
        case .invalidResponse: return "Сервер вернул некорректный WebDAV XML."
        case .missingCredential: return "Пароль подключения не найден. Создайте подключение заново."
        case .unsupportedLocation: return "Сервер вернул путь вне выбранного WebDAV-хранилища."
        case .fileTooLarge: return "Ответ каталога WebDAV слишком большой."
        case .invalidName: return "Недопустимое имя файла или папки."
        case .rootMutation: return "Корневую папку подключения нельзя переименовывать или удалять."
        case .targetExists: return "Нельзя перезаписать существующий файл или папку."
        }
    }
}

struct WebDAVServer: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var baseURL: String
    var username: String

    var root: URL? { URL(string: baseURL) }
}

struct WebDAVAccess {
    let server: WebDAVServer
    let password: String

    var authorizationHeader: String? {
        guard !server.username.isEmpty else { return nil }
        let text = "\(server.username):\(password)"
        return "Basic " + Data(text.utf8).base64EncodedString()
    }
}

enum WebDAVURLPolicy {
    static func root(from raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var parts = URLComponents(string: trimmed),
              parts.scheme?.lowercased() == "https",
              parts.host != nil,
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil else {
            throw WebDAVError.invalidURL
        }
        parts.scheme = "https"
        if !parts.percentEncodedPath.hasSuffix("/") {
            parts.percentEncodedPath += "/"
        }
        guard let url = parts.url else { throw WebDAVError.invalidURL }
        return url
    }

    static func isWithinRoot(_ candidate: URL, root: URL) -> Bool {
        guard let a = URLComponents(url: candidate, resolvingAgainstBaseURL: false),
              let b = URLComponents(url: root, resolvingAgainstBaseURL: false),
              a.scheme?.lowercased() == "https",
              a.host?.lowercased() == b.host?.lowercased(),
              (a.port ?? 443) == (b.port ?? 443),
              a.user == nil, a.password == nil, a.query == nil, a.fragment == nil else {
            return false
        }
        // Reject traversal, including percent-encoded dot segments. The HTTP
        // client must never follow hrefs outside the configured root.
        let decoded = a.percentEncodedPath.removingPercentEncoding ?? a.path
        let base = b.percentEncodedPath.removingPercentEncoding ?? b.path
        let normalized = decoded.split(separator: "/", omittingEmptySubsequences: true)
        guard !normalized.contains(where: { $0 == "." || $0 == ".." }) else {
            return false
        }
        let normalizedBase = base.hasSuffix("/") ? base : base + "/"
        return decoded == String(normalizedBase.dropLast())
            || decoded.hasPrefix(normalizedBase)
    }

    static func resolve(href: String, directory: URL, root: URL) -> URL? {
        let value = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              let candidate = URL(string: value, relativeTo: directory)?.absoluteURL,
              isWithinRoot(candidate, root: root) else {
            return nil
        }
        return candidate
    }

    static func child(named raw: String, in directory: URL, root: URL,
                      isDirectory: Bool) throws -> URL {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..",
              !name.hasPrefix("."),
              !name.contains("/"), !name.contains("\\"),
              !name.contains("?"), !name.contains("#"),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              isWithinRoot(directory, root: root) else {
            throw WebDAVError.invalidName
        }
        let candidate = directory.appendingPathComponent(name, isDirectory: isDirectory)
        guard isWithinRoot(candidate, root: root),
              isDirectChild(candidate, of: directory) else {
            throw WebDAVError.unsupportedLocation
        }
        return candidate
    }

    static func isDirectChild(_ child: URL, of directory: URL) -> Bool {
        let parent = directory.path.hasSuffix("/") ? directory.path : directory.path + "/"
        let path = child.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let prefix = parent.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let childParent = (path as NSString).deletingLastPathComponent
        return childParent == prefix && path != prefix
    }
}

private final class WebDAVRedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private struct DavParsedEntry: Decodable {
    let href: String
    let displayName: String
    let isDirectory: Bool
    let size: UInt64?

    enum CodingKeys: String, CodingKey {
        case href
        case displayName = "display_name"
        case isDirectory = "is_directory"
        case size
    }
}

private func decodeDAVMultistatus(_ data: Data) throws -> [DavParsedEntry] {
    guard !data.isEmpty && data.count <= 8 * 1024 * 1024 else {
        throw WebDAVError.fileTooLarge
    }
    let entries: [DavParsedEntry]? = data.withUnsafeBytes { bytes in
        guard let pointer = bytes.bindMemory(to: UInt8.self).baseAddress,
              let result = vidrane_webdav_parse_json(pointer, UInt(data.count)) else {
            return nil
        }
        defer { vidrane_webdav_free_json(result) }
        return try? JSONDecoder().decode(
            [DavParsedEntry].self,
            from: Data(String(cString: result).utf8)
        )
    }
    guard let entries else { throw WebDAVError.invalidResponse }
    return entries
}

final class WebDAVClient {
    static let shared = WebDAVClient()
    private let session: URLSession

    // Dependency injection keeps production TLS and redirect rules unchanged
    // while allowing deterministic URLProtocol-based transport tests.
    init(session: URLSession = .shared) {
        self.session = session
    }

    private func request(_ url: URL, access: WebDAVAccess, method: String) throws -> URLRequest {
        guard let root = access.server.root,
              WebDAVURLPolicy.isWithinRoot(url, root: root) else {
            throw WebDAVError.unsupportedLocation
        }
        var result = URLRequest(url: url)
        result.httpMethod = method
        result.timeoutInterval = 35
        if let auth = access.authorizationHeader {
            result.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        return result
    }

    private func check(_ response: URLResponse, allowed: Set<Int>) throws {
        guard let http = response as? HTTPURLResponse else { throw WebDAVError.invalidResponse }
        if (300...399).contains(http.statusCode) { throw WebDAVError.forbiddenResponse }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw WebDAVError.authenticationRequired
        }
        guard allowed.contains(http.statusCode) else {
            throw WebDAVError.serverError(http.statusCode)
        }
    }

    func list(directory: URL, access: WebDAVAccess) async throws -> [WebDAVEntry] {
        guard let root = access.server.root else { throw WebDAVError.invalidURL }
        var canonicalDirectory = directory
        if !canonicalDirectory.path.hasSuffix("/") {
            canonicalDirectory.appendPathComponent("", isDirectory: true)
        }
        var request = try request(canonicalDirectory, access: access, method: "PROPFIND")
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <d:propfind xmlns:d="DAV:">
          <d:prop><d:resourcetype/><d:displayname/><d:getcontentlength/></d:prop>
        </d:propfind>
        """.utf8)
        let (data, response) = try await session.data(
            for: request, delegate: WebDAVRedirectBlocker()
        )
        try check(response, allowed: [207])
        guard data.count < 8 * 1024 * 1024 else { throw WebDAVError.fileTooLarge }
        let parsed = try decodeDAVMultistatus(data)
        return parsed.compactMap { item in
            guard let url = WebDAVURLPolicy.resolve(
                href: item.href, directory: canonicalDirectory, root: root
            ),
            WebDAVURLPolicy.isDirectChild(url, of: canonicalDirectory) else {
                return nil
            }
            let inferred = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
            return WebDAVEntry(
                url: url,
                name: item.displayName.isEmpty ? inferred : item.displayName,
                isDirectory: item.isDirectory,
                size: item.size.flatMap(Int64.init(exactly:))
            )
        }
        .sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func mutation(_ request: URLRequest, allowed: Set<Int>) async throws {
        let (_, response) = try await session.data(
            for: request, delegate: WebDAVRedirectBlocker()
        )
        try check(response, allowed: allowed)
    }

    private func checkedSource(_ url: URL, access: WebDAVAccess) throws {
        guard let root = access.server.root,
              WebDAVURLPolicy.isWithinRoot(url, root: root) else {
            throw WebDAVError.unsupportedLocation
        }
        let target = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let rootPath = root.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if target == rootPath { throw WebDAVError.rootMutation }
    }

    /// MKCOL adds a directory with no filesystem changes outside the root.
    func createDirectory(named name: String, in directory: URL,
                         access: WebDAVAccess) async throws {
        guard let root = access.server.root else { throw WebDAVError.invalidURL }
        let destination = try WebDAVURLPolicy.child(
            named: name, in: directory, root: root, isDirectory: true
        )
        let request = try request(destination, access: access, method: "MKCOL")
        try await mutation(request, allowed: [201])
    }

    /// MOVE/COPY are performed by the server; they require DAV Level 2
    /// support for some providers. Overwrite: F prevents silent replacement.
    func transfer(_ source: WebDAVEntry, into directory: URL,
                  named name: String, copy: Bool,
                  access: WebDAVAccess) async throws {
        try checkedSource(source.url, access: access)
        guard let root = access.server.root else { throw WebDAVError.invalidURL }
        let destination = try WebDAVURLPolicy.child(
            named: name, in: directory, root: root,
            isDirectory: source.isDirectory
        )
        if source.url == destination { throw WebDAVError.targetExists }
        if source.isDirectory {
            let origin = source.url.path.hasSuffix("/") ? source.url.path : source.url.path + "/"
            if destination.path.hasPrefix(origin) {
                throw WebDAVError.unsupportedLocation
            }
        }
        var request = try request(
            source.url, access: access, method: copy ? "COPY" : "MOVE"
        )
        request.setValue(destination.absoluteString, forHTTPHeaderField: "Destination")
        request.setValue("F", forHTTPHeaderField: "Overwrite")
        try await mutation(request, allowed: [201, 204])
    }

    /// DELETE is destructive and must only be initiated after UI confirmation.
    func delete(_ entry: WebDAVEntry, access: WebDAVAccess) async throws {
        try checkedSource(entry.url, access: access)
        let request = try request(entry.url, access: access, method: "DELETE")
        try await mutation(request, allowed: [200, 202, 204])
    }

    /// PUT with a precondition refuses overwriting an existing resource.
    /// This is intentionally a foreground upload, not a persistent queue.
    func upload(_ localURL: URL, in directory: URL,
                access: WebDAVAccess) async throws {
        guard localURL.isFileURL,
              let root = access.server.root else { throw WebDAVError.invalidURL }
        let destination = try WebDAVURLPolicy.child(
            named: localURL.lastPathComponent,
            in: directory, root: root, isDirectory: false
        )
        let scoped = localURL.startAccessingSecurityScopedResource()
        defer { if scoped { localURL.stopAccessingSecurityScopedResource() } }
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: localURL.path, isDirectory: &isFolder),
              !isFolder.boolValue else { throw WebDAVError.invalidResponse }

        var request = try request(destination, access: access, method: "PUT")
        request.setValue("*", forHTTPHeaderField: "If-None-Match")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.upload(
            for: request, fromFile: localURL, delegate: WebDAVRedirectBlocker()
        )
        try check(response, allowed: [201, 204])
    }

    /// Retrieves an authenticated WebDAV file to a temporary URL.
    /// Caller is responsible for moving/deleting the file. Redirects are
    /// rejected so that Basic credentials aren't forwarded elsewhere.
    func download(file: URL, access: WebDAVAccess) async throws -> URL {
        let request = try request(file, access: access, method: "GET")
        let (temporary, response) = try await session.download(
            for: request, delegate: WebDAVRedirectBlocker()
        )
        try check(response, allowed: [200, 206])
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("webdav-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }
}
