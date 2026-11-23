import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// Server must honor HTTP byte ranges. Without that guarantee, AVFoundation
/// could accidentally download an entire video for one metadata request.
enum WebDAVStreamError: LocalizedError {
    case unsupportedRange
    case invalidResponse
    case invalidRange
    case stopped

    var errorDescription: String? {
        switch self {
        case .unsupportedRange:
            return "Сервер не поддерживает HTTP Range. Используйте «Скачать и воспроизвести»."
        case .invalidResponse:
            return "Некорректный ответ WebDAV-сервера при потоковом чтении."
        case .invalidRange:
            return "Сервер вернул неверный диапазон байтов."
        case .stopped:
            return "Поток был остановлен."
        }
    }
}

private final class StreamRedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Never forward an Authorization header to a redirected origin.
        completionHandler(nil)
    }
}

/// Validates the *entire* Content-Range, not only "Accept-Ranges".
/// A valid response is exactly: bytes START-END/TOTAL.
private enum RangeResponse {
    static func parse(_ header: String) -> (start: Int64, end: Int64, total: Int64)? {
        let parts = header.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 2, parts[0].lowercased() == "bytes",
              let pair = parts[1].split(separator: "/", omittingEmptySubsequences: false)
                .first.map(String.init),
              let totalText = parts[1].split(separator: "/", omittingEmptySubsequences: false)
                .last.map(String.init),
              let total = Int64(totalText), total > 0 else { return nil }
        let offsets = pair.split(separator: "-", omittingEmptySubsequences: false)
        guard offsets.count == 2,
              let start = Int64(offsets[0]), let end = Int64(offsets[1]),
              start >= 0, end >= start, end < total else { return nil }
        return (start, end, total)
    }

    static func matches(_ response: URLResponse, start: Int64,
                        end: Int64, total: Int64?) -> Bool {
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 206,
              let header = http.value(forHTTPHeaderField: "Content-Range"),
              let range = parse(header),
              range.start == start, range.end == end else { return false }
        return total == nil || range.total == total
    }
}

/// AVFoundation byte-range resource-loader backed by authenticated HTTPS DAV.
/// The original server URL, Basic header and credentials never appear in the
/// synthetic asset URL or app's saved library.
final class WebDAVRangeStream: NSObject, AVAssetResourceLoaderDelegate {
    static let allowedExtensions: Set<String> = [
        "mp4", "m4v", "mov", "mp3", "m4a", "aac", "wav", "caf"
    ]

    private let origin: URL
    private let authorization: String?
    private let length: Int64
    private let contentType: String
    private let transport: URLSession
    private let worker = DispatchQueue(label: "org.vidrane.webdav.range-loader")
    private var inflight: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var closed = false
    private let syntheticURL: URL

    lazy var asset: AVURLAsset = {
        let asset = AVURLAsset(url: syntheticURL)
        asset.resourceLoader.setDelegate(self, queue: worker)
        return asset
    }()

    private init(origin: URL, authorization: String?, length: Int64,
                 contentType: String, transport: URLSession, filename: String) {
        self.origin = origin
        self.authorization = authorization
        self.length = length
        self.contentType = contentType
        self.transport = transport
        syntheticURL = URL(string: "vidrane-dav://asset/\(UUID().uuidString)")!
            .appendingPathComponent(filename)
        super.init()
    }

    /// Probe with one byte so unsupported servers cannot initiate a full file
    /// download. Successful probing also obtains authoritative file length.
    static func open(file: WebDAVEntry, access: WebDAVAccess) async throws -> WebDAVRangeStream {
        guard !file.isDirectory,
              allowedExtensions.contains(file.url.pathExtension.lowercased()),
              let root = access.server.root,
              WebDAVURLPolicy.isWithinRoot(file.url, root: root) else {
            throw WebDAVError.unsupportedLocation
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        let transport = URLSession(
            configuration: configuration,
            delegate: StreamRedirectBlocker(),
            delegateQueue: nil
        )

        do {
            var probe = URLRequest(url: file.url)
            probe.httpMethod = "GET"
            probe.cachePolicy = .reloadIgnoringLocalCacheData
            probe.timeoutInterval = 30
            probe.setValue("bytes=0-0", forHTTPHeaderField: "Range")
            if let authorization = access.authorizationHeader {
                probe.setValue(authorization, forHTTPHeaderField: "Authorization")
            }
            let (bytes, response) = try await transport.bytes(for: probe)
            defer { bytes.task.cancel() }
            if let http = response as? HTTPURLResponse, http.statusCode == 401 ||
                (response as? HTTPURLResponse)?.statusCode == 403 {
                throw WebDAVError.authenticationRequired
            }
            guard RangeResponse.matches(response, start: 0, end: 0, total: nil),
                  let http = response as? HTTPURLResponse,
                  let value = http.value(forHTTPHeaderField: "Content-Range"),
                  let range = RangeResponse.parse(value) else {
                throw WebDAVStreamError.unsupportedRange
            }
            var iterator = bytes.makeAsyncIterator()
            guard try await iterator.next() != nil else {
                throw WebDAVStreamError.invalidResponse
            }
            let type = UTType(filenameExtension: file.name.components(separatedBy: ".").last ?? "")
                ?? .data
            return WebDAVRangeStream(
                origin: file.url,
                authorization: access.authorizationHeader,
                length: range.total,
                contentType: type.identifier,
                transport: transport,
                filename: file.name
            )
        } catch {
            transport.invalidateAndCancel()
            throw error
        }
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard !closed, request.request.url?.scheme == syntheticURL.scheme,
              request.request.url?.host == syntheticURL.host else { return false }

        if let info = request.contentInformationRequest {
            info.contentType = contentType
            info.contentLength = length
            info.isByteRangeAccessSupported = true
        }

        guard let data = request.dataRequest else {
            request.finishLoading()
            return true
        }

        let start = max(data.requestedOffset, data.currentOffset)
        guard start >= 0, start < length else {
            request.finishLoading(with: WebDAVStreamError.invalidRange)
            return true
        }
        let needed = data.requestsAllDataToEndOfResource
            ? length - start
            : min(length - start, Int64(data.requestedLength))
        guard needed > 0 else {
            request.finishLoading()
            return true
        }

        let id = ObjectIdentifier(request)
        inflight[id] = Task { [weak self] in
            guard let self else { return }
            do {
                var offset = start
                let finish = start + needed
                while offset < finish {
                    try Task.checkCancellation()
                    let count = Int(min(256 * 1024, finish - offset))
                    let chunk = try await self.getRange(start: offset, count: count)
                    self.worker.async {
                        guard self.inflight[id] != nil else { return }
                        request.dataRequest?.respond(with: chunk)
                    }
                    offset += Int64(chunk.count)
                }
                self.worker.async {
                    guard self.inflight.removeValue(forKey: id) != nil else { return }
                    request.finishLoading()
                }
            } catch {
                self.worker.async {
                    guard self.inflight.removeValue(forKey: id) != nil else { return }
                    request.finishLoading(with: error)
                }
            }
        }
        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel request: AVAssetResourceLoadingRequest
    ) {
        inflight.removeValue(forKey: ObjectIdentifier(request))?.cancel()
    }

    private func getRange(start: Int64, count: Int) async throws -> Data {
        guard count > 0, count <= 256 * 1024 else { throw WebDAVStreamError.invalidRange }
        let end = start + Int64(count) - 1
        var req = URLRequest(url: origin)
        req.httpMethod = "GET"
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 45
        req.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        if let authorization { req.setValue(authorization, forHTTPHeaderField: "Authorization") }
        let (bytes, response) = try await transport.bytes(for: req)
        defer { bytes.task.cancel() }
        guard RangeResponse.matches(response, start: start, end: end, total: length) else {
            throw WebDAVStreamError.invalidResponse
        }
        var data = Data()
        data.reserveCapacity(count)
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < count else { throw WebDAVStreamError.invalidResponse }
            data.append(byte)
            if data.count == count { break }
        }
        guard data.count == count else { throw WebDAVStreamError.invalidResponse }
        return data
    }

    /// Cancels outstanding ranges when the playback screen is dismissed.
    func close() {
        worker.async {
            guard !self.closed else { return }
            self.closed = true
            for task in self.inflight.values { task.cancel() }
            self.inflight.removeAll()
            self.transport.invalidateAndCancel()
        }
    }
}
