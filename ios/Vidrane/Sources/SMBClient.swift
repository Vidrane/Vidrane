import AMSMB2
import Foundation

struct SMBEntry: Identifiable, Hashable {
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64?
    var id: String { path }
}

/// A separate SMB3-encrypted share connection. SMB1 and unencrypted
/// transport downgrades are intentionally not allowed.
final class SMBConnection {
    private let client: SMB2Manager
    private let root: String

    private init(client: SMB2Manager, root: String) {
        self.client = client
        self.root = root
    }

    static func connect(server: SMBServer, password: String) async throws -> SMBConnection {
        var uri = URLComponents()
        uri.scheme = "smb"
        uri.host = server.host
        uri.port = server.port
        guard let url = uri.url else { throw SMBError.invalidConnection }
        let credential = URLCredential(
            user: server.username, password: password, persistence: .none
        )
        guard let client = SMB2Manager(
            url: url, domain: server.domain, credential: credential
        ) else { throw SMBError.invalidConnection }
        try await client.connectShare(name: server.share, encrypted: true)
        return SMBConnection(client: client, root: server.root)
    }

    func close() async {
        try? await client.disconnectShare(gracefully: true)
    }

    private func checked(_ path: String) throws -> String {
        let normalized = try SMBPath.normalized(path)
        guard SMBPath.allowed(normalized, root: root) else {
            throw SMBError.outsideShare
        }
        return normalized
    }

    /// Reject symlinks as navigation components when reported by the server.
    /// Does not claim to protect against a malicious SMB server changing
    /// filesystem mappings between requests.
    private func checkAncestors(_ path: String) async throws {
        let parts = path.split(separator: "/")
        for i in parts.indices {
            let component = parts[...i].joined(separator: "/")
            let attrs = try await client.attributesOfItem(atPath: component)
            if attrs[.isSymbolicLinkKey] as? Bool == true ||
                attrs[.fileResourceTypeKey] as? URLFileResourceType == .symbolicLink {
                throw SMBError.outsideShare
            }
        }
    }

    func list(_ path: String) async throws -> [SMBEntry] {
        let directory = try checked(path)
        if !directory.isEmpty { try await checkAncestors(directory) }
        let attrs = try await client.contentsOfDirectory(atPath: directory)
        return attrs.compactMap { row in
            guard let name = row[.nameKey] as? String,
                  let path = try? SMBPath.child(name, directory: directory, root: root)
            else { return nil }
            let kind = row[.fileResourceTypeKey] as? URLFileResourceType
            let isDirectory = kind == .directory || row[.isDirectoryKey] as? Bool == true
            let isFile = kind == .regular || row[.isRegularFileKey] as? Bool == true
            guard isDirectory || isFile else { return nil }
            let size = (row[.fileSizeKey] as? NSNumber)?.int64Value
            return SMBEntry(name: name, path: path, isDirectory: isDirectory, size: size)
        }.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func fileSize(_ entry: SMBEntry) async throws -> Int64 {
        guard !entry.isDirectory else { throw SMBError.unsupported }
        let path = try checked(entry.path)
        try await checkAncestors(path)
        let attrs = try await client.attributesOfItem(atPath: path)
        guard let value = attrs[.fileSizeKey] as? NSNumber,
              value.int64Value > 0 else { throw SMBError.unsupported }
        return value.int64Value
    }

    /// Read one small random-access range for media playback.
    func read(_ entry: SMBEntry, offset: Int64, count: Int) async throws -> Data {
        let path = try checked(entry.path)
        guard !entry.isDirectory, offset >= 0,
              count > 0, count <= 128 * 1024,
              offset <= Int64.max - Int64(count) else { throw SMBError.invalidPath }
        let begin = UInt64(offset)
        let end = begin + UInt64(count)
        var result = Data()
        for try await chunk in client.contents(atPath: path, range: begin..<end) {
            try Task.checkCancellation()
            guard result.count + chunk.count <= count else {
                throw SMBError.truncated
            }
            result.append(chunk)
        }
        guard result.count == count else { throw SMBError.truncated }
        return result
    }

    func download(_ entry: SMBEntry, progress: @escaping (Int64, Int64?) -> Bool) async throws -> URL {
        guard !entry.isDirectory else { throw SMBError.unsupported }
        let path = try checked(entry.path)
        try await checkAncestors(path)
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("vidrane-smb-\(UUID().uuidString)")
        do {
            try await client.downloadItem(atPath: path, to: output) { received, total in
                progress(received, total > 0 ? total : nil)
            }
            return output
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }

    func createDirectory(named name: String, in directory: String) async throws {
        let parent = try checked(directory)
        if !parent.isEmpty { try await checkAncestors(parent) }
        try await client.createDirectory(
            atPath: SMBPath.child(name, directory: parent, root: root)
        )
    }

    func remove(_ entry: SMBEntry) async throws {
        guard entry.path != root else { throw SMBError.outsideShare }
        let path = try checked(entry.path)
        try await checkAncestors(path)
        if entry.isDirectory {
            try await client.removeDirectory(atPath: path, recursive: false)
        } else {
            try await client.removeFile(atPath: path)
        }
    }
}
