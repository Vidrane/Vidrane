import Foundation

private final class MockDAV: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, url.host == "dav.example.invalid",
              request.value(forHTTPHeaderField: "Authorization") == "Basic dGVzdDpmaXh0dXJl" else {
            client?.urlProtocol(self, didFailWithError: URLError(.userAuthenticationRequired))
            return
        }
        var status = 500
        var body = Data()
        switch (request.httpMethod, url.path) {
        case ("PROPFIND", "/media"), ("PROPFIND", "/media/"):
            guard request.value(forHTTPHeaderField: "Depth") == "1" else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            status = 207
            body = Data("""
            <multistatus xmlns="DAV:">
              <response><href>/media/</href><propstat><prop><resourcetype><collection/></resourcetype></prop><status>HTTP/1.1 200 OK</status></propstat></response>
              <response><href>/media/episode%201.mkv</href><propstat><prop><displayname>Episode 1</displayname><getcontentlength>42</getcontentlength></prop><status>HTTP/1.1 200 OK</status></propstat></response>
              <response><href>https://evil.example.invalid/media/evil.mkv</href></response>
              <response><href>/outside/secret.mkv</href></response>
              <response><href>/media/sub/deep.mkv</href></response>
              <response><href>/media/%2e%2e/secret.mkv</href></response>
            </multistatus>
            """.utf8)
        case ("PROPFIND", "/media/denied"), ("PROPFIND", "/media/denied/"):
            status = 401
        case ("PROPFIND", "/media/bad"), ("PROPFIND", "/media/bad/"):
            status = 207
            body = Data("<not-dav/>".utf8)
        case ("MKCOL", "/media/new"), ("MKCOL", "/media/new/"):
            status = 201
        case ("COPY", "/media/episode 1.mkv"):
            status = request.value(forHTTPHeaderField: "Overwrite") == "F"
                && request.value(forHTTPHeaderField: "Destination") == "https://dav.example.invalid/media/copy.mkv" ? 201 : 412
        case ("DELETE", "/media/episode 1.mkv"):
            status = 204
        default: break
        }
        guard let response = HTTPURLResponse(url: url, statusCode: status,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/xml"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct WebDAVClientSmoke {
    static func main() async throws {
        let root = try WebDAVURLPolicy.root(from: "https://dav.example.invalid/media")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockDAV.self]
        config.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let client = WebDAVClient(session: session)
        let server = WebDAVServer(id: UUID(), title: "fixture", baseURL: root.absoluteString, username: "test")
        let access = WebDAVAccess(server: server, password: "fixture")
        let entries = try await client.list(directory: root, access: access)
        precondition(entries.count == 1)
        precondition(entries[0].name == "Episode 1" && entries[0].size == 42)
        try await client.createDirectory(named: "new", in: root, access: access)
        try await client.transfer(entries[0], into: root, named: "copy.mkv", copy: true, access: access)
        try await client.delete(entries[0], access: access)
        do {
            let entry = WebDAVEntry(url: root, name: "root", isDirectory: true, size: nil)
            try await client.delete(entry, access: access)
            fatalError("root deletion accepted")
        } catch WebDAVError.rootMutation {}
        do {
            _ = try await client.list(directory: root.appendingPathComponent("denied"), access: access)
            fatalError("401 accepted")
        } catch WebDAVError.authenticationRequired {}
        do {
            _ = try await client.list(directory: root.appendingPathComponent("bad"), access: access)
            fatalError("malformed XML accepted")
        } catch WebDAVError.invalidResponse {}
        precondition(!WebDAVURLPolicy.isWithinRoot(URL(string: "https://dav.example.invalid/media-other/a")!, root: root))
        precondition(!WebDAVURLPolicy.isWithinRoot(URL(string: "http://dav.example.invalid/media/a")!, root: root))
        precondition(!WebDAVURLPolicy.isWithinRoot(URL(string: "https://dav.example.invalid:444/media/a")!, root: root))
        print("WebDAV client request, path and XML integration checks passed")
    }
}
