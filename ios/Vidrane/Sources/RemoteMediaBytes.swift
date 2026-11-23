import Foundation

/// A seekable bounded remote file, independent of the network protocol.
/// Implementations never return more bytes than requested.
protocol RemoteMediaBytes: AnyObject {
    var length: Int64 { get }
    func read(offset: Int64, count: Int) async throws -> Data
    func close() async
}

actor SFTPRemoteBytes: RemoteMediaBytes {
    nonisolated let length: Int64
    private let handle: SFTPReadHandle

    init(handle: SFTPReadHandle) {
        self.handle = handle
        self.length = handle.size
    }

    func read(offset: Int64, count: Int) async throws -> Data {
        try await handle.read(offset: offset, count: count)
    }

    func close() async {
        await handle.close()
    }
}

actor SMBRemoteBytes: RemoteMediaBytes {
    nonisolated let length: Int64
    private let client: SMBConnection
    private let entry: SMBEntry

    init(client: SMBConnection, entry: SMBEntry, length: Int64) {
        self.client = client
        self.entry = entry
        self.length = length
    }

    func read(offset: Int64, count: Int) async throws -> Data {
        try await client.read(entry, offset: offset, count: count)
    }

    func close() async {
        await client.close()
    }
}

private final class RemoteDAVRedirectBlocker: NSObject, URLSessionTaskDelegate {
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

/// Direct authenticated HTTPS Range reader for the local libmpv relay.
/// Fails closed if the server returns HTTP 200 or an invalid Content-Range.
actor WebDAVRemoteBytes: RemoteMediaBytes {
    nonisolated let length: Int64
    private let url: URL
    private let authorization: String?
    private let session: URLSession

    private init(url: URL, authorization: String?, session: URLSession, length: Int64) {
        self.url = url
        self.authorization = authorization
        self.session = session
        self.length = length
    }

    static func connect(entry: WebDAVEntry, access: WebDAVAccess) async throws -> WebDAVRemoteBytes {
        guard !entry.isDirectory, let root = access.server.root,
              WebDAVURLPolicy.isWithinRoot(entry.url, root: root) else {
            throw WebDAVError.unsupportedLocation
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        let session = URLSession(
            configuration: configuration,
            delegate: RemoteDAVRedirectBlocker(),
            delegateQueue: nil
        )
        do {
            var request = URLRequest(url: entry.url)
            request.httpMethod = "GET"
            request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            request.cachePolicy = .reloadIgnoringLocalCacheData
            if let header = access.authorizationHeader {
                request.setValue(header, forHTTPHeaderField: "Authorization")
            }
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse,
                  let range = http.value(forHTTPHeaderField: "Content-Range"),
                  http.statusCode == 206 else {
                throw WebDAVStreamError.unsupportedRange
            }
            let total = range.withCString {
                vidrane_content_range_total($0, 0, 0, 0)
            }
            guard total > 0, total <= UInt64(Int64.max) else {
                throw WebDAVStreamError.invalidRange
            }
            var iterator = bytes.makeAsyncIterator()
            guard try await iterator.next() != nil else {
                throw WebDAVStreamError.invalidResponse
            }
            return WebDAVRemoteBytes(
                url: entry.url, authorization: access.authorizationHeader,
                session: session, length: Int64(total)
            )
        } catch {
            session.invalidateAndCancel()
            throw error
        }
    }

    func read(offset: Int64, count: Int) async throws -> Data {
        guard offset >= 0, count > 0, count <= 128 * 1024,
              Int64(count) <= length - offset else {
            throw WebDAVStreamError.invalidRange
        }
        let end = offset + Int64(count) - 1
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 45
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("bytes=\(offset)-\(end)", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if let authorization { request.setValue(authorization, forHTTPHeaderField: "Authorization") }
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 206,
              (http.value(forHTTPHeaderField: "Content-Encoding") ?? "identity").lowercased() == "identity",
              let range = http.value(forHTTPHeaderField: "Content-Range"),
              range.withCString({
                  vidrane_content_range_total(
                      $0, UInt64(offset), UInt64(end), UInt64(length)
                  )
              }) == UInt64(length) else {
            throw WebDAVStreamError.invalidResponse
        }
        var result = Data()
        result.reserveCapacity(count)
        for try await byte in bytes {
            try Task.checkCancellation()
            guard result.count < count else { throw WebDAVStreamError.invalidResponse }
            result.append(byte)
            if result.count == count { break }
        }
        guard result.count == count else { throw WebDAVStreamError.invalidResponse }
        return result
    }

    func close() async {
        session.invalidateAndCancel()
    }
}
