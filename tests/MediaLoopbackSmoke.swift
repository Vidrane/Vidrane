import Foundation

private actor MockRemote: RemoteMediaBytes {
    nonisolated let length: Int64 = 300_000
    private var calls = 0
    private var closed = false

    func read(offset: Int64, count: Int) async throws -> Data {
        guard !closed, count > 0, count <= 128 * 1024,
              offset >= 0, Int64(count) <= length - offset else {
            throw URLError(.cannotDecodeContentData)
        }
        calls += 1
        return Data((offset..<(offset + Int64(count))).map { UInt8($0 % 251) })
    }

    func close() async { closed = true }
    func reads() -> Int { calls }
}

@main
struct MediaLoopbackSmoke {
    static func main() async throws {
        let source = MockRemote()
        let relay = try await MediaLoopbackRelay.start(source: source, filename: "fixture.mkv")
        defer { relay.stop() }
        precondition(relay.url.host == "127.0.0.1")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        func request(_ url: URL, _ range: String? = nil, method: String = "GET") async throws -> (Data, HTTPURLResponse) {
            var req = URLRequest(url: url)
            req.httpMethod = method
            if let range { req.setValue(range, forHTTPHeaderField: "Range") }
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            return (data, http)
        }
        let head = try await request(relay.url, method: "HEAD")
        precondition(head.1.statusCode == 200 && head.0.isEmpty)
        precondition(head.1.value(forHTTPHeaderField: "Content-Length") == "300000")
        let before = await source.reads()
        precondition(before == 0)
        let seek = try await request(relay.url, "bytes=130000-140000")
        precondition(seek.1.statusCode == 206)
        precondition(seek.1.value(forHTTPHeaderField: "Content-Range") == "bytes 130000-140000/300000")
        precondition(seek.0 == Data((130000...140000).map { UInt8($0 % 251) }))
        let suffix = try await request(relay.url, "bytes=-16")
        precondition(suffix.0 == Data((299984..<300000).map { UInt8($0 % 251) }))
        let invalid = try await request(relay.url, "bytes=300000-")
        precondition(invalid.1.statusCode == 416)
        let multiple = try await request(relay.url, "bytes=0-1,5-6")
        precondition(multiple.1.statusCode == 416)
        let invalidURL = relay.url.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("invalid/file.mkv")
        let rejected = try await request(invalidURL)
        precondition(rejected.1.statusCode == 403)
        let full = try await request(relay.url)
        precondition(full.1.statusCode == 200)
        precondition(full.0 == Data((0..<300000).map { UInt8($0 % 251) }))
        print("Loopback HTTP Range integration checks passed")
    }
}
