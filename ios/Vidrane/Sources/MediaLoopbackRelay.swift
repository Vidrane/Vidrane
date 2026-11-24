import Foundation
import Network

enum RelayError: LocalizedError {
    case unavailable
    case malformedRequest
    case invalidRange
    case closed

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Не удалось запустить локальный медиамост."
        case .malformedRequest: return "Медиаплеер отправил неверный HTTP-запрос."
        case .invalidRange: return "Неверный диапазон файла."
        case .closed: return "Медиапоток закрыт."
        }
    }
}

/// Loopback-only HTTP Range transport for libmpv. It is deliberately not
/// exposed on Wi-Fi/LAN interfaces and has no public listener. A 256-bit
/// per-session secret is embedded in the local URL path. No remote account
/// credentials appear in that URL. The backend source performs real SSH,
/// HTTPS or SMB3 reads as libmpv seeks.
final class MediaLoopbackRelay {
    let url: URL
    let length: Int64

    private let source: any RemoteMediaBytes
    private let listener: NWListener
    private let token: String
    private let queue = DispatchQueue(label: "org.vidrane.media-loopback")
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var sockets: [ObjectIdentifier: NWConnection] = [:]
    private var stopped = false

    private init(
        source: any RemoteMediaBytes,
        listener: NWListener, token: String,
        port: UInt16, filename: String
    ) {
        self.source = source
        self.listener = listener
        self.token = token
        self.length = source.length
        let base = URL(string: "http://127.0.0.1:\(port)/\(token)/")!
        self.url = base.appendingPathComponent(filename)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
    }

    static func start(
        source: any RemoteMediaBytes, filename: String
    ) async throws -> MediaLoopbackRelay {
        guard source.length > 0 else { throw RelayError.invalidRange }
        let options = NWParameters.tcp
        // REQUIRED: never bind to 0.0.0.0, :: or an external interface.
        options.requiredLocalEndpoint = .hostPort(
            host: NWEndpoint.Host("127.0.0.1"), port: .any
        )
        options.allowLocalEndpointReuse = false

        let listener = try NWListener(using: options, on: .any)
        listener.newConnectionHandler = { $0.cancel() }
        let startQueue = DispatchQueue(label: "org.vidrane.media-loopback-start")
        let gate = NSLock()
        var completed = false
        let assignedPort: UInt16
        do {
            assignedPort = try await withCheckedThrowingContinuation { continuation in
                listener.stateUpdateHandler = { state in
                    gate.lock()
                    defer { gate.unlock() }
                    guard !completed else { return }
                    switch state {
                    case .ready:
                        guard let port = listener.port else {
                            completed = true
                            continuation.resume(throwing: RelayError.unavailable)
                            return
                        }
                        completed = true
                        continuation.resume(returning: port.rawValue)
                    case .failed:
                        completed = true
                        continuation.resume(throwing: RelayError.unavailable)
                    case .cancelled:
                        completed = true
                        continuation.resume(throwing: RelayError.closed)
                    default:
                        break
                    }
                }
                listener.start(queue: startQueue)
            }
        } catch {
            listener.cancel()
            await source.close()
            throw error
        }
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "") +
            UUID().uuidString.replacingOccurrences(of: "-", with: "")
        return MediaLoopbackRelay(
            source: source, listener: listener, token: token,
            port: assignedPort, filename: filename
        )
    }

    private func accept(_ connection: NWConnection) {
        queue.async {
            guard !self.stopped, self.sockets.count < 8 else {
                connection.cancel()
                return
            }
            let id = ObjectIdentifier(connection)
            self.sockets[id] = connection
            connection.start(queue: self.queue)
            self.tasks[id] = Task { [weak self] in
                guard let self else { return }
                await self.serve(connection)
                self.queue.async {
                    self.sockets.removeValue(forKey: id)
                    self.tasks.removeValue(forKey: id)
                    connection.cancel()
                }
            }
        }
    }

    private func receiveHeaders(_ connection: NWConnection) async throws -> String {
        var buffer = Data()
        while buffer.count <= 8192 {
            try Task.checkCancellation()
            let data: Data = try await withCheckedThrowingContinuation { continuation in
                connection.receive(
                    minimumIncompleteLength: 1, maximumLength: 8192 - buffer.count
                ) { data, _, complete, error in
                    if error != nil || (complete && (data?.isEmpty ?? true)) {
                        continuation.resume(throwing: RelayError.closed)
                    } else if let data, !data.isEmpty {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: RelayError.malformedRequest)
                    }
                }
            }
            buffer.append(data)
            if buffer.range(of: Data("\r\n\r\n".utf8)) != nil {
                guard let text = String(data: buffer, encoding: .utf8) else {
                    throw RelayError.malformedRequest
                }
                return text
            }
            if buffer.count == 8192 { throw RelayError.malformedRequest }
        }
        throw RelayError.malformedRequest
    }

    private func send(_ bytes: Data, to connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: bytes, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func sendError(_ code: Int, to connection: NWConnection) async {
        let response = "HTTP/1.1 \(code) Error\r\nConnection: close\r\nContent-Length: 0\r\nCache-Control: no-store\r\n\r\n"
        try? await send(Data(response.utf8), to: connection)
    }

    private func serve(_ connection: NWConnection) async {
        var sentHeaders = false
        do {
            let header = try await receiveHeaders(connection)
            let lines = header.components(separatedBy: "\r\n")
            guard let first = lines.first else { throw RelayError.malformedRequest }
            let firstParts = first.split(separator: " ")
            guard firstParts.count == 3,
                  firstParts[0] == "GET" || firstParts[0] == "HEAD",
                  firstParts[2].hasPrefix("HTTP/1."),
                  firstParts[1].hasPrefix("/\(token)/") else {
                await sendError(403, to: connection)
                return
            }

            var requestedRange: String?
            for line in lines.dropFirst() {
                let components = line.split(separator: ":", maxSplits: 1)
                guard components.count == 2 else { continue }
                if components[0].lowercased() == "range" {
                    if requestedRange != nil { throw RelayError.invalidRange }
                    requestedRange = components[1].trimmingCharacters(in: .whitespaces)
                }
            }

            var start: Int64 = 0
            var end = length - 1
            let partial = requestedRange != nil
            if let requestedRange {
                guard requestedRange.hasPrefix("bytes="),
                      !requestedRange.contains(",") else {
                    throw RelayError.invalidRange
                }
                let value = String(requestedRange.dropFirst(6))
                let pieces = value.split(separator: "-", omittingEmptySubsequences: false)
                guard pieces.count == 2 else { throw RelayError.invalidRange }
                if pieces[0].isEmpty {
                    guard let suffix = Int64(pieces[1]), suffix > 0 else {
                        throw RelayError.invalidRange
                    }
                    start = max(0, length - suffix)
                } else {
                    guard let offset = Int64(pieces[0]), offset >= 0,
                          offset < length else { throw RelayError.invalidRange }
                    start = offset
                    if !pieces[1].isEmpty {
                        guard let desiredEnd = Int64(pieces[1]), desiredEnd >= start else {
                            throw RelayError.invalidRange
                        }
                        end = min(end, desiredEnd)
                    }
                }
            }

            let size = end - start + 1
            let head = (partial ? "HTTP/1.1 206 Partial Content" : "HTTP/1.1 200 OK") +
                "\r\nContent-Type: application/octet-stream" +
                "\r\nAccept-Ranges: bytes\r\nContent-Length: \(size)" +
                (partial ? "\r\nContent-Range: bytes \(start)-\(end)/\(length)" : "") +
                "\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
            sentHeaders = true
            try await send(Data(head.utf8), to: connection)
            guard firstParts[0] == "GET" else { return }

            var offset = start
            while offset <= end {
                try Task.checkCancellation()
                let count = Int(min(128 * 1024, end - offset + 1))
                let chunk = try await source.read(offset: offset, count: count)
                guard chunk.count == count else { throw RelayError.invalidRange }
                try await send(chunk, to: connection)
                offset += Int64(count)
            }
        } catch {
            // After a successful header, a second HTTP response would be
            // interpreted as media bytes. Close the truncated body instead.
            if !sentHeaders { await sendError(416, to: connection) }
        }
    }

    func stop() {
        queue.async {
            guard !self.stopped else { return }
            self.stopped = true
            self.listener.cancel()
            for task in self.tasks.values { task.cancel() }
            for socket in self.sockets.values { socket.cancel() }
            self.tasks.removeAll()
            self.sockets.removeAll()
            Task { await self.source.close() }
        }
    }
}
