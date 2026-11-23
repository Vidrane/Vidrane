import Foundation
import SwiftUI

enum DownloadStatus: String {
    case running
    case finished
    case failed
    case cancelled

    var description: String {
        switch self {
        case .running: return "Скачивание"
        case .finished: return "Готово"
        case .failed: return "Ошибка"
        case .cancelled: return "Отменено"
        }
    }
}

struct DownloadRecord: Identifiable {
    let id: UUID
    let name: String
    var status: DownloadStatus
    var receivedBytes: Int64 = 0
    var expectedBytes: Int64?
    var error: String?

    var fraction: Double? {
        guard let expectedBytes, expectedBytes > 0 else { return nil }
        return min(1, max(0, Double(receivedBytes) / Double(expectedBytes)))
    }
}

/// The access URL and any Authorization header are kept in RAM only, never
/// added to the visible model or user defaults. No download credentials
/// are printed in error messages.
private final class DownloadContext {
    let request: URLRequest
    let filename: String
    let playWhenFinished: Bool
    weak var library: MediaLibrary?
    var task: URLSessionDownloadTask?

    init(request: URLRequest, filename: String,
         playWhenFinished: Bool, library: MediaLibrary) {
        self.request = request
        self.filename = filename
        self.playWhenFinished = playWhenFinished
        self.library = library
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    weak var owner: TransferCenter?

    init(owner: TransferCenter) { self.owner = owner }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Never leak Authorization to a redirect target.
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let id = downloadTask.taskDescription
        Task { @MainActor [weak owner] in
            owner?.progress(
                taskID: id,
                taskIdentifier: downloadTask.taskIdentifier,
                bytes: totalBytesWritten,
                total: totalBytesExpectedToWrite
            )
        }
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let id = downloadTask.taskDescription
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode
        // URLSession removes the temporary download when this delegate
        // callback returns. Move it to a private temporary location first.
        var safeLocation: URL?
        var failure: String?
        if status == 200 {
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("vidrane-transfer-\(UUID().uuidString)")
            do {
                try FileManager.default.moveItem(at: location, to: destination)
                safeLocation = destination
            } catch {
                failure = "Не удалось сохранить временный файл."
            }
        } else {
            failure = "Сервер вернул HTTP \(status ?? 0)."
        }
        Task { @MainActor [weak owner] in
            owner?.completed(
                taskID: id,
                taskIdentifier: downloadTask.taskIdentifier,
                temporary: safeLocation,
                error: failure
            )
        }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        let id = task.taskDescription
        Task { @MainActor [weak owner] in
            owner?.failed(taskID: id, taskIdentifier: task.taskIdentifier, error: error)
        }
    }
}

/// Foreground download manager with live progress, cancellation and retries.
/// Background URLSession and durable resume-data storage are future work.
@MainActor
final class TransferCenter: ObservableObject {
    static let shared = TransferCenter()

    @Published private(set) var records: [DownloadRecord] = []
    private var contexts: [UUID: DownloadContext] = [:]
    private lazy var delegate = DownloadDelegate(owner: self)
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: delegate, delegateQueue: .main)
    }()

    private init() {}

    func isDownloading(_ url: URL) -> Bool {
        contexts.values.contains {
            $0.request.url == url && $0.task?.state == .running
        }
    }

    func enqueue(
        url: URL, filename: String,
        authorization: String? = nil,
        playWhenFinished: Bool = false,
        library: MediaLibrary
    ) throws {
        guard url.scheme?.lowercased() == "https",
              url.host != nil, url.user == nil, url.password == nil else {
            throw WebDAVError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 120
        if let authorization {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        let name = (filename as NSString).lastPathComponent
        let displayName = name.isEmpty ? "download" : name
        let id = UUID()
        contexts[id] = DownloadContext(
            request: request, filename: displayName,
            playWhenFinished: playWhenFinished, library: library
        )
        records.insert(
            DownloadRecord(id: id, name: displayName, status: .running),
            at: 0
        )
        start(id)
    }

    func cancel(_ id: UUID) {
        guard let context = contexts[id], let row = index(id),
              records[row].status == .running else { return }
        context.task?.cancel()
        records[row].status = .cancelled
    }

    func retry(_ id: UUID) {
        guard let row = index(id), contexts[id] != nil,
              records[row].status == .failed || records[row].status == .cancelled else {
            return
        }
        records[row].status = .running
        records[row].receivedBytes = 0
        records[row].expectedBytes = nil
        records[row].error = nil
        start(id)
    }

    func remove(_ id: UUID) {
        contexts[id]?.task?.cancel()
        contexts.removeValue(forKey: id)
        records.removeAll { $0.id == id }
    }

    private func index(_ id: UUID) -> Int? {
        records.firstIndex { $0.id == id }
    }

    private func start(_ id: UUID) {
        guard let context = contexts[id] else { return }
        let task = session.downloadTask(with: context.request)
        task.taskDescription = id.uuidString
        context.task = task
        task.resume()
    }

    func progress(taskID: String?, taskIdentifier: Int, bytes: Int64, total: Int64) {
        guard let taskID, let id = UUID(uuidString: taskID),
              let row = index(id), records[row].status == .running,
              contexts[id]?.task?.taskIdentifier == taskIdentifier else { return }
        records[row].receivedBytes = bytes
        records[row].expectedBytes = total > 0 ? total : nil
    }

    func completed(taskID: String?, taskIdentifier: Int, temporary: URL?, error: String?) {
        guard let taskID, let id = UUID(uuidString: taskID),
              let row = index(id), let context = contexts[id],
              records[row].status == .running,
              context.task?.taskIdentifier == taskIdentifier else {
            if let temporary { try? FileManager.default.removeItem(at: temporary) }
            return
        }
        context.task = nil
        if let error {
            records[row].status = .failed
            records[row].error = error
            return
        }
        guard let temporary, let library = context.library else {
            records[row].status = .failed
            records[row].error = "Файл не был получен."
            return
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            let file = try library.importRemoteFile(at: temporary, filename: context.filename)
            records[row].status = .finished
            records[row].receivedBytes = file.bytes
            records[row].expectedBytes = file.bytes
            if context.playWhenFinished && file.kind.playable {
                library.play(file)
            }
            // Do not retain HTTP Authorization headers longer than necessary.
            contexts.removeValue(forKey: id)
        } catch {
            records[row].status = .failed
            records[row].error = "Не удалось импортировать скачанный файл."
        }
    }

    func failed(taskID: String?, taskIdentifier: Int, error: Error) {
        guard let taskID, let id = UUID(uuidString: taskID),
              let row = index(id), records[row].status == .running,
              contexts[id]?.task?.taskIdentifier == taskIdentifier else { return }
        records[row].status = .failed
        records[row].error = (error as? URLError)?.code == .cancelled
            ? "Соединение прервано." : "Ошибка сети: \(error.localizedDescription)"
        contexts[id]?.task = nil
    }
}
