import Foundation
import Security
import SwiftUI

enum DownloadStatus: String, Codable {
    case waiting
    case running
    case finished
    case failed
    case cancelled

    var description: String {
        switch self {
        case .waiting: return "В очереди / восстановление"
        case .running: return "Скачивание"
        case .finished: return "Готово"
        case .failed: return "Ошибка"
        case .cancelled: return "Отменено"
        }
    }
}

struct DownloadRecord: Identifiable, Codable {
    let id: UUID
    let name: String
    var source: String = "HTTPS"
    var status: DownloadStatus
    var receivedBytes: Int64 = 0
    var expectedBytes: Int64?
    var error: String?

    var fraction: Double? {
        guard let expectedBytes, expectedBytes > 0 else { return nil }
        return min(1, max(0, Double(receivedBytes) / Double(expectedBytes)))
    }
}

private enum TransferKind: String, Codable {
    case https, webdav, sftp, smb
}

private struct TransferJournalEntry: Codable {
    var record: DownloadRecord
    let kind: TransferKind
    let serverID: UUID?
    let remotePath: String?
    var etag: String? = nil
    var autoPlay: Bool
}

private final class TransferRedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// Journal and .part files live in Application Support. Account passwords
/// stay in the existing server Keychains. Direct HTTPS URLs (including
/// signed query tokens) are stored only in Keychain, not in the JSON journal.
///
/// Transfers are foreground tasks. On launch interrupted tasks return to
/// "waiting" and automatically continue when the MediaLibrary is attached.
/// Supported providers resume from verified partial byte offsets.
@MainActor
final class TransferCenter: ObservableObject {
    static let shared = TransferCenter()

    @Published private(set) var records: [DownloadRecord] = []
    private var journal: [UUID: TransferJournalEntry] = [:]
    private var work: [UUID: Task<Void, Never>] = [:]
    private var generations: [UUID: UUID] = [:]
    private weak var mediaLibrary: MediaLibrary?
    private let fm = FileManager.default
    private let base: URL
    private let journalFile: URL
    private let secretService = "org.vidrane.transfer.url"
    private var lastSaved = Date.distantPast

    private init() {
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        base = support.appendingPathComponent("TransferParts", isDirectory: true)
        journalFile = support.appendingPathComponent("transfer-queue-v2.json")
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)

        if let bytes = try? Data(contentsOf: journalFile),
           let recovered = try? JSONDecoder().decode([TransferJournalEntry].self, from: bytes) {
            for var item in recovered {
                if item.record.status == .running {
                    item.record.status = .waiting
                    item.autoPlay = false
                }
                journal[item.record.id] = item
                records.append(item.record)
            }
        }
    }

    /// AppRootView calls this after launching. The journal may have been
    /// restored before its MediaLibrary environment object existed.
    func attach(library: MediaLibrary) {
        mediaLibrary = library
        pump()
    }

    func isDownloading(_ url: URL) -> Bool {
        records.contains { record in
            guard record.status == .running || record.status == .waiting,
                  let job = journal[record.id],
                  job.kind == .https || job.kind == .webdav,
                  let stored = try? secret(for: record.id) else { return false }
            return stored == url.absoluteString
        }
    }

    func isDownloadingSFTP(server: SFTPServer, entry: SFTPEntry) -> Bool {
        records.contains { record in
            guard let job = journal[record.id] else { return false }
            return (record.status == .running || record.status == .waiting) &&
                job.kind == .sftp && job.serverID == server.id &&
                job.remotePath == entry.path
        }
    }

    func enqueue(
        url: URL, filename: String,
        source: String = "HTTPS",
        serverID: UUID? = nil,
        authorization: String? = nil,
        playWhenFinished: Bool = false,
        library: MediaLibrary
    ) throws {
        guard url.scheme?.lowercased() == "https", url.host != nil,
              url.user == nil, url.password == nil else { throw WebDAVError.invalidURL }
        let kind: TransferKind = source == "WebDAV" ? .webdav : .https
        guard kind != .webdav || serverID != nil else {
            throw WebDAVError.missingCredential
        }
        let id = UUID()
        try saveSecret(url.absoluteString, for: id)
        let name = (filename as NSString).lastPathComponent
        let record = DownloadRecord(
            id: id, name: name.isEmpty ? "download" : name,
            source: kind == .webdav ? "WebDAV" : "HTTPS", status: .waiting
        )
        journal[id] = TransferJournalEntry(
            record: record, kind: kind, serverID: serverID,
            remotePath: nil, etag: nil, autoPlay: playWhenFinished
        )
        records.insert(record, at: 0)
        attach(library: library)
        persist()
        pump()
    }

    func enqueueSFTP(
        server: SFTPServer, entry: SFTPEntry,
        playWhenFinished: Bool = false, library: MediaLibrary
    ) {
        guard !entry.isDirectory, !isDownloadingSFTP(server: server, entry: entry)
        else { return }
        insertJob(
            kind: .sftp, serverID: server.id,
            path: entry.path, name: entry.name,
            size: entry.size, play: playWhenFinished,
            library: library
        )
    }

    func enqueueSMB(
        server: SMBServer, entry: SMBEntry,
        playWhenFinished: Bool = false, library: MediaLibrary
    ) {
        guard !entry.isDirectory else { return }
        if records.contains(where: {
            guard let item = journal[$0.id] else { return false }
            return ($0.status == .running || $0.status == .waiting) &&
                item.kind == .smb && item.serverID == server.id &&
                item.remotePath == entry.path
        }) { return }
        insertJob(
            kind: .smb, serverID: server.id,
            path: entry.path, name: entry.name,
            size: entry.size, play: playWhenFinished,
            library: library
        )
    }

    private func insertJob(
        kind: TransferKind, serverID: UUID, path: String,
        name: String, size: Int64?, play: Bool,
        library: MediaLibrary
    ) {
        let id = UUID()
        let record = DownloadRecord(
            id: id, name: name, source: kind == .smb ? "SMB" : "SFTP",
            status: .waiting, expectedBytes: size
        )
        journal[id] = TransferJournalEntry(
            record: record, kind: kind, serverID: serverID,
            remotePath: path, autoPlay: play
        )
        records.insert(record, at: 0)
        attach(library: library)
        persist()
        pump()
    }

    func cancel(_ id: UUID) {
        guard let row = index(id),
              records[row].status == .running || records[row].status == .waiting
        else { return }
        records[row].status = .cancelled
        journal[id]?.record = records[row]
        work[id]?.cancel()
        persist()
    }

    func retry(_ id: UUID) {
        guard let row = index(id),
              records[row].status == .failed || records[row].status == .cancelled
        else { return }
        records[row].status = .waiting
        records[row].error = nil
        journal[id]?.record = records[row]
        persist()
        pump()
    }

    func remove(_ id: UUID) {
        work[id]?.cancel()
        work.removeValue(forKey: id)
        generations.removeValue(forKey: id)
        journal.removeValue(forKey: id)
        records.removeAll { $0.id == id }
        try? fm.removeItem(at: partURL(id))
        deleteSecret(for: id)
        persist()
        pump()
    }

    private func index(_ id: UUID) -> Int? {
        records.firstIndex(where: { $0.id == id })
    }

    private func partURL(_ id: UUID) -> URL {
        base.appendingPathComponent(id.uuidString + ".part")
    }

    private func pump() {
        guard mediaLibrary != nil else { return }
        let active = work.values.count
        guard active < 2 else { return }
        for row in records where row.status == .waiting {
            if work.count >= 2 { break }
            let id = row.id
            guard work[id] == nil, journal[id] != nil else { continue }
            let generation = UUID()
            generations[id] = generation
            if let index = index(id) {
                records[index].status = .running
                journal[id]?.record = records[index]
            }
            work[id] = Task { [weak self] in
                guard let self else { return }
                await self.perform(id, generation: generation)
            }
        }
        persist()
    }

    private func progress(_ id: UUID, generation: UUID,
                          bytes: Int64, expected: Int64?) {
        guard generations[id] == generation, let row = index(id),
              records[row].status == .running else { return }
        records[row].receivedBytes = bytes
        if let expected, expected > 0 { records[row].expectedBytes = expected }
        journal[id]?.record = records[row]
        persist(throttled: true)
    }

    private func perform(_ id: UUID, generation: UUID) async {
        do {
            guard let entry = journal[id] else { return }
            let length: Int64
            switch entry.kind {
            case .https, .webdav:
                length = try await downloadHTTP(id, generation: generation, entry: entry)
            case .sftp:
                length = try await downloadSFTP(id, generation: generation, entry: entry)
            case .smb:
                length = try await downloadSMB(id, generation: generation, entry: entry)
            }
            try Task.checkCancellation()
            guard generations[id] == generation,
                  let row = index(id), records[row].status == .running,
                  let library = mediaLibrary else { throw CancellationError() }

            let item = try library.importRemoteFile(
                at: partURL(id), filename: entry.record.name
            )
            records[row].status = .finished
            records[row].receivedBytes = length
            records[row].expectedBytes = length
            journal[id]?.record = records[row]
            journal[id]?.autoPlay = false
            deleteSecret(for: id)
            if entry.autoPlay && item.kind.playable { library.play(item) }
        } catch {
            guard generations[id] == generation,
                  let row = index(id) else { return }
            if records[row].status == .running {
                records[row].status = error is CancellationError ? .cancelled : .failed
                records[row].error = error is CancellationError
                    ? nil : "Передача не завершена: \(error.localizedDescription)"
                journal[id]?.record = records[row]
            }
        }
        if generations[id] == generation {
            work.removeValue(forKey: id)
            generations.removeValue(forKey: id)
            persist()
            pump()
        }
    }

    private func actualPartSize(_ id: UUID) -> Int64 {
        let size = (try? fm.attributesOfItem(atPath: partURL(id).path)[.size] as? NSNumber)?.int64Value
        return max(0, size ?? 0)
    }

    /// If resuming from partial data, compare its final bytes to the
    /// same offset on the remote server to prevent joining mismatched media.
    private func verifiedOffset(
        _ id: UUID, expected: Int64, fetch: (Int64, Int) async throws -> Data
    ) async throws -> Int64 {
        try await RemoteTransferPolicy.verifiedOffset(
            partial: partURL(id), expected: expected, fetch: fetch
        )
    }

    private func prepareOutput(_ id: UUID, offset: Int64) throws -> FileHandle {
        if !fm.fileExists(atPath: partURL(id).path) {
            guard fm.createFile(atPath: partURL(id).path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let file = try FileHandle(forWritingTo: partURL(id))
        try file.truncate(atOffset: UInt64(offset))
        try file.seek(toOffset: UInt64(offset))
        return file
    }

    private func downloadSFTP(
        _ id: UUID, generation: UUID, entry: TransferJournalEntry
    ) async throws -> Int64 {
        guard let serverID = entry.serverID,
              let server = SFTPStore.shared.servers.first(where: { $0.id == serverID }),
              let path = entry.remotePath else { throw SFTPError.invalidServer }
        let secret = try SFTPStore.shared.password(for: server)
        let client = try await SFTPConnection.connect(server: server, password: secret)
        let remote = SFTPEntry(name: entry.record.name, path: path, isDirectory: false, size: nil)
        let handle: SFTPReadHandle
        do { handle = try await client.openReadStream(remote) }
        catch { await client.close(); throw error }
        defer { Task { await handle.close() } }

        let length = handle.size
        let offset = try await verifiedOffset(id, expected: length) {
            try await handle.read(offset: $0, count: $1)
        }
        let output = try prepareOutput(id, offset: offset)
        defer { try? output.close() }
        return try await RemoteTransferPolicy.copy(
            length: length, offset: offset, chunkSize: 64 * 1024, output: output,
            fetch: { try await handle.read(offset: $0, count: $1) },
            progress: { self.progress(id, generation: generation, bytes: $0, expected: length) }
        )
    }

    private func downloadSMB(
        _ id: UUID, generation: UUID, entry: TransferJournalEntry
    ) async throws -> Int64 {
        guard let serverID = entry.serverID,
              let server = SMBStore.shared.servers.first(where: { $0.id == serverID }),
              let path = entry.remotePath else { throw SMBError.invalidConnection }
        let secret = try SMBStore.shared.password(for: server)
        let client = try await SMBConnection.connect(server: server, password: secret)
        defer { Task { await client.close() } }
        let remote = SMBEntry(name: entry.record.name, path: path, isDirectory: false, size: nil)
        let length = try await client.fileSize(remote)
        let offset = try await verifiedOffset(id, expected: length) {
            try await client.read(remote, offset: $0, count: $1)
        }
        let output = try prepareOutput(id, offset: offset)
        defer { try? output.close() }
        return try await RemoteTransferPolicy.copy(
            length: length, offset: offset, chunkSize: 128 * 1024, output: output,
            fetch: { try await client.read(remote, offset: $0, count: $1) },
            progress: { self.progress(id, generation: generation, bytes: $0, expected: length) }
        )
    }

    private func downloadHTTP(
        _ id: UUID, generation: UUID, entry: TransferJournalEntry
    ) async throws -> Int64 {
        let address = try secret(for: id)
        guard let url = URL(string: address), url.scheme == "https",
              url.user == nil, url.password == nil else {
            throw WebDAVError.invalidURL
        }

        var auth: String?
        if entry.kind == .webdav {
            guard let serverID = entry.serverID,
                  let server = WebDAVStore.shared.servers.first(where: { $0.id == serverID }),
                  let root = server.root,
                  WebDAVURLPolicy.isWithinRoot(url, root: root) else {
                throw WebDAVError.missingCredential
            }
            auth = try WebDAVStore.shared.access(server).authorizationHeader
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        let session = URLSession(
            configuration: configuration,
            delegate: TransferRedirectBlocker(),
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        var offset = actualPartSize(id)
        // Without a stable ETag we do not assume an old HTTP partial is
        // still the same object after a process restart.
        if offset > 0 && entry.etag == nil {
            try? fm.removeItem(at: partURL(id))
            offset = 0
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 120
        request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if let auth { request.setValue(auth, forHTTPHeaderField: "Authorization") }
        if offset > 0, let etag = entry.etag {
            request.setValue(etag, forHTTPHeaderField: "If-Range")
        }

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200 || http.statusCode == 206,
              (http.value(forHTTPHeaderField: "Content-Encoding") ?? "identity").lowercased() == "identity" else {
            throw WebDAVError.invalidResponse
        }

        var expected: Int64?
        if http.statusCode == 206 {
            guard let header = http.value(forHTTPHeaderField: "Content-Range"),
                  let range = Self.parseRange(header, offset: offset) else {
                throw WebDAVStreamError.invalidRange
            }
            expected = range
            if offset > 0, let previous = entry.etag,
               let new = http.value(forHTTPHeaderField: "ETag"),
               new != previous {
                throw WebDAVStreamError.invalidResponse
            }
        } else {
            // Server ignored Range or the object changed: re-download from
            // byte zero without mixing old and new file contents.
            offset = 0
            if let len = http.value(forHTTPHeaderField: "Content-Length") {
                expected = Int64(len)
            }
        }

        if let tag = http.value(forHTTPHeaderField: "ETag"),
           !tag.hasPrefix("W/") && !tag.contains("\n") {
            journal[id]?.etag = tag
        } else if offset == 0 {
            journal[id]?.etag = nil
        }
        let output = try prepareOutput(id, offset: offset)
        defer { try? output.close() }
        var written = offset
        var batch = Data()
        batch.reserveCapacity(64 * 1024)

        progress(id, generation: generation, bytes: written, expected: expected)
        for try await byte in bytes {
            if batch.count == 64 * 1024 {
                try Task.checkCancellation()
                try output.write(contentsOf: batch)
                written += Int64(batch.count)
                batch.removeAll(keepingCapacity: true)
                progress(id, generation: generation, bytes: written, expected: expected)
            }
            batch.append(byte)
        }
        try Task.checkCancellation()
        if !batch.isEmpty {
            try output.write(contentsOf: batch)
            written += Int64(batch.count)
        }
        guard written > 0, expected == nil || expected == written else {
            throw WebDAVStreamError.invalidResponse
        }
        progress(id, generation: generation, bytes: written, expected: written)
        return written
    }

    private static func parseRange(_ header: String, offset: Int64) -> Int64? {
        guard offset >= 0 else { return nil }
        let total = header.withCString { vidrane_download_range_total($0, UInt64(offset)) }
        guard total > 0, total <= UInt64(Int64.max) else { return nil }
        return Int64(total)
    }

    private func persist(throttled: Bool = false) {
        if throttled && Date().timeIntervalSince(lastSaved) < 1.5 { return }
        lastSaved = Date()
        let snapshot = records.compactMap { journal[$0.id] }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: journalFile, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    private func saveSecret(_ value: String, for id: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: secretService,
            kSecAttrAccount as String: id.uuidString,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(
                domain: NSOSStatusErrorDomain, code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Не удалось защитить URL в Keychain."]
            )
        }
    }

    private func secret(for id: UUID) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: secretService,
            kSecAttrAccount as String: id.uuidString,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let bytes = result as? Data,
              let value = String(data: bytes, encoding: .utf8) else {
            throw WebDAVError.missingCredential
        }
        return value
    }

    private func deleteSecret(for id: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: secretService,
            kSecAttrAccount as String: id.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }
}
