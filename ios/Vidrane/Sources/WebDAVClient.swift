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

private final class WebDAVXMLParser: NSObject, XMLParserDelegate {
    struct RawEntry {
        var href = ""
        var displayName = ""
        var directory = false
        var length: Int64?
    }

    private(set) var responses: [RawEntry] = []
    private var entry: RawEntry?
    private var activeElement = ""
    private var body = ""
    private var insideResourceType = false

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String : String] = [:]) {
        let name = elementName.split(separator: ":").last.map(String.init)?.lowercased() ?? ""
        if name == "response" { entry = RawEntry() }
        if name == "resourcetype" { insideResourceType = true }
        if name == "collection" && insideResourceType { entry?.directory = true }
        activeElement = name
        body = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        body += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.split(separator: ":").last.map(String.init)?.lowercased() ?? ""
        if name == "href" { entry?.href = body.trimmingCharacters(in: .whitespacesAndNewlines) }
        if name == "displayname" { entry?.displayName = body.trimmingCharacters(in: .whitespacesAndNewlines) }
        if name == "getcontentlength" {
            entry?.length = Int64(body.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if name == "resourcetype" { insideResourceType = false }
        if name == "response", let finished = entry {
            responses.append(finished)
            entry = nil
        }
        activeElement = ""
        body = ""
    }

    func parse(_ data: Data) throws -> [RawEntry] {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = self
        guard parser.parse() else { throw WebDAVError.invalidResponse }
        return responses
    }
}

final class WebDAVClient {
    static let shared = WebDAVClient()
    private init() {}

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
        let (data, response) = try await URLSession.shared.data(
            for: request, delegate: WebDAVRedirectBlocker()
        )
        try check(response, allowed: [207])
        guard data.count < 8 * 1024 * 1024 else { throw WebDAVError.fileTooLarge }
        let parsed = try WebDAVXMLParser().parse(data)
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
                isDirectory: item.directory,
                size: item.length
            )
        }
        .sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Retrieves an authenticated WebDAV file to a temporary URL.
    /// Caller is responsible for moving/deleting the file. Redirects are
    /// rejected so that Basic credentials aren't forwarded elsewhere.
    func download(file: URL, access: WebDAVAccess) async throws -> URL {
        let request = try request(file, access: access, method: "GET")
        let (temporary, response) = try await URLSession.shared.download(
            for: request, delegate: WebDAVRedirectBlocker()
        )
        try check(response, allowed: [200, 206])
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("webdav-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }
}
