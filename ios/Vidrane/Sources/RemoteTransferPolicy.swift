import Foundation

enum RemoteTransferError: LocalizedError {
    case invalidLength
    case invalidChunk

    var errorDescription: String? {
        switch self {
        case .invalidLength: return "Некорректный размер удалённого файла."
        case .invalidChunk: return "Удалённый сервер вернул неполный блок данных."
        }
    }
}

/// Shared resume and exact-byte copying rules. The adapters own transport
/// authentication and handles; the caller owns the journal and output file.
enum RemoteTransferPolicy {
    static func verifiedOffset(
        partial: URL, expected: Int64,
        fetch: (Int64, Int) async throws -> Data
    ) async throws -> Int64 {
        guard expected >= 0 else { throw RemoteTransferError.invalidLength }
        let fm = FileManager.default
        guard fm.fileExists(atPath: partial.path) else { return 0 }
        let attributes = try fm.attributesOfItem(atPath: partial.path)
        guard let current = (attributes[.size] as? NSNumber)?.int64Value,
              current >= 0 else { throw RemoteTransferError.invalidLength }
        guard current > 0 else { return 0 }
        guard current <= expected else { return 0 }
        let count = Int(min(4096, current))
        let file = try FileHandle(forReadingFrom: partial)
        defer { try? file.close() }
        try file.seek(toOffset: UInt64(current - Int64(count)))
        let local = try file.read(upToCount: count) ?? Data()
        try Task.checkCancellation()
        let remote = try await fetch(current - Int64(count), count)
        try Task.checkCancellation()
        guard local.count == count, remote.count == count else {
            throw RemoteTransferError.invalidChunk
        }
        return local == remote ? current : 0
    }

    static func copy(
        length: Int64, offset: Int64, chunkSize: Int, output: FileHandle,
        fetch: (Int64, Int) async throws -> Data,
        progress: (Int64) -> Void
    ) async throws -> Int64 {
        guard length >= 0, offset >= 0, offset <= length,
              chunkSize > 0, chunkSize <= 128 * 1024 else {
            throw RemoteTransferError.invalidLength
        }
        var written = offset
        progress(written)
        while written < length {
            try Task.checkCancellation()
            let count = Int(min(Int64(chunkSize), length - written))
            let data = try await fetch(written, count)
            try Task.checkCancellation()
            guard data.count == count else { throw RemoteTransferError.invalidChunk }
            try output.write(contentsOf: data)
            written += Int64(count)
            progress(written)
        }
        return written
    }
}
