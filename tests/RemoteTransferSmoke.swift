import Foundation

@main
struct RemoteTransferSmoke {
    static func main() async throws {
        let fm = FileManager.default
        let path = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: path) }
        let payload = Data((0..<200_000).map { UInt8($0 % 251) })
        func read(_ offset: Int64, _ count: Int) async throws -> Data {
            payload.subdata(in: Int(offset)..<(Int(offset) + count))
        }
        try payload.prefix(70_000).write(to: path)
        let start = try await RemoteTransferPolicy.verifiedOffset(
            partial: path, expected: Int64(payload.count), fetch: read
        )
        precondition(start == 70_000)
        let file = try FileHandle(forWritingTo: path)
        defer { try? file.close() }
        try file.seek(toOffset: UInt64(start))
        var checkpoints: [Int64] = []
        let end = try await RemoteTransferPolicy.copy(
            length: Int64(payload.count), offset: start, chunkSize: 65536,
            output: file, fetch: read, progress: { checkpoints.append($0) }
        )
        precondition(end == Int64(payload.count))
        precondition(checkpoints.first == start && checkpoints.last == end)
        let completed = try Data(contentsOf: path)
        precondition(completed == payload)

        var changed = payload
        changed[changed.count - 1] ^= 1
        let reset = try await RemoteTransferPolicy.verifiedOffset(
            partial: path, expected: Int64(changed.count),
            fetch: { offset, count in changed.subdata(in: Int(offset)..<(Int(offset) + count)) }
        )
        precondition(reset == 0)
        let oversized = try await RemoteTransferPolicy.verifiedOffset(
            partial: path, expected: 10, fetch: read
        )
        precondition(oversized == 0)
        try file.truncate(atOffset: 0)
        try file.seek(toOffset: 0)
        do {
            _ = try await RemoteTransferPolicy.copy(
                length: 100, offset: 0, chunkSize: 50, output: file,
                fetch: { _, _ in Data() }, progress: { _ in }
            )
            fatalError("zero-byte read accepted")
        } catch RemoteTransferError.invalidChunk {}
        let afterShort = try file.offset()
        precondition(afterShort == 0)
        do {
            _ = try await RemoteTransferPolicy.copy(
                length: 100, offset: 0, chunkSize: 50, output: file,
                fetch: { offset, count in
                    if offset > 0 { throw URLError(.networkConnectionLost) }
                    return try await read(offset, count)
                }, progress: { _ in }
            )
            fatalError("interruption ignored")
        } catch let error as URLError {
            precondition(error.code == .networkConnectionLost)
        }
        let interrupted = try Data(contentsOf: path)
        precondition(interrupted == payload.prefix(50))
        let resumed = try await RemoteTransferPolicy.verifiedOffset(
            partial: path, expected: 100, fetch: read
        )
        precondition(resumed == 50)
        print("Remote transfer interruption/resume checks passed")
    }
}
