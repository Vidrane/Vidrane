import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// SFTP random-access playback via AVAssetResourceLoader. The synthetic URL
/// does not contain a password, username, host or remote file path.
/// No local copy of the complete video is made.
final class SFTPRangeStream: NSObject, AVAssetResourceLoaderDelegate {
    static let allowedExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mp3", "m4a", "aac", "wav", "caf"
    ]

    private let source: SFTPReadHandle
    private let filename: String
    private let queue = DispatchQueue(label: "org.vidrane.sftp.range-loader")
    private var pending: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var stopped = false
    private let syntheticURL: URL

    lazy var asset: AVURLAsset = {
        let result = AVURLAsset(url: syntheticURL)
        result.resourceLoader.setDelegate(self, queue: queue)
        return result
    }()

    private init(source: SFTPReadHandle, filename: String) {
        self.source = source
        self.filename = filename
        self.syntheticURL = URL(
            string: "vidrane-sftp://asset/\(UUID().uuidString)"
        )!.appendingPathComponent(filename)
        super.init()
    }

    /// Caller obtains the password from the iOS Keychain. SSH host-key
    /// verification is enforced by SFTPConnection before opening a file.
    static func open(
        server: SFTPServer, password: String, entry: SFTPEntry
    ) async throws -> SFTPRangeStream {
        guard !entry.isDirectory,
              allowedExtensions.contains(
                (entry.name as NSString).pathExtension.lowercased()
              ) else { throw SFTPError.unsupportedEntry }

        let connection = try await SFTPConnection.connect(
            server: server, password: password
        )
        do {
            let handle = try await connection.openReadStream(entry)
            return SFTPRangeStream(source: handle, filename: entry.name)
        } catch {
            await connection.close()
            throw error
        }
    }

    func resourceLoader(
        _ loader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard !stopped,
              request.request.url?.scheme == syntheticURL.scheme,
              request.request.url?.host == syntheticURL.host else { return false }

        if let info = request.contentInformationRequest {
            let ext = (filename as NSString).pathExtension.lowercased()
            info.contentType = (UTType(filenameExtension: ext) ?? .data).identifier
            info.contentLength = source.size
            info.isByteRangeAccessSupported = true
        }

        guard let data = request.dataRequest else {
            request.finishLoading()
            return true
        }
        let start = max(data.requestedOffset, data.currentOffset)
        guard start >= 0, start < source.size else {
            request.finishLoading(with: SFTPError.invalidPath)
            return true
        }
        let count: Int64 = data.requestsAllDataToEndOfResource
            ? source.size - start
            : min(source.size - start, Int64(data.requestedLength))
        guard count > 0 else {
            request.finishLoading()
            return true
        }

        let id = ObjectIdentifier(request)
        pending[id] = Task { [weak self] in
            guard let self else { return }
            do {
                var offset = start
                let end = start + count
                while offset < end {
                    try Task.checkCancellation()
                    let length = Int(min(64 * 1024, end - offset))
                    let chunk = try await self.source.read(
                        offset: offset, count: length
                    )
                    self.queue.async {
                        guard !self.stopped, self.pending[id] != nil else { return }
                        request.dataRequest?.respond(with: chunk)
                    }
                    offset += Int64(chunk.count)
                }
                self.queue.async {
                    guard self.pending.removeValue(forKey: id) != nil,
                          !self.stopped else { return }
                    request.finishLoading()
                }
            } catch {
                self.queue.async {
                    guard self.pending.removeValue(forKey: id) != nil,
                          !self.stopped else { return }
                    request.finishLoading(with: error)
                }
            }
        }
        return true
    }

    func resourceLoader(
        _ loader: AVAssetResourceLoader,
        didCancel request: AVAssetResourceLoadingRequest
    ) {
        pending.removeValue(forKey: ObjectIdentifier(request))?.cancel()
    }

    func close() {
        queue.async {
            guard !self.stopped else { return }
            self.stopped = true
            for task in self.pending.values { task.cancel() }
            self.pending.removeAll()
            Task { await self.source.close() }
        }
    }
}
