import Citadel
import Foundation
import NIO
import NIOSSH

struct SFTPEntry: Identifiable, Hashable {
    var name: String
    var path: String
    var isDirectory: Bool
    var size: Int64?
    var id: String { path }
}

/// Each operation owns a short-lived authenticated SSH/SFTP connection.
/// No passwords or SSH keys are embedded in media URLs.
final class SFTPConnection {
    private let ssh: SSHClient
    private let sftp: Citadel.SFTPClient
    private let canonicalRoot: String
    private let declaredRoot: String

    private init(ssh: SSHClient, sftp: Citadel.SFTPClient, canonicalRoot: String, declaredRoot: String) {
        self.ssh = ssh
        self.sftp = sftp
        self.canonicalRoot = canonicalRoot
        self.declaredRoot = declaredRoot
    }

    static func connect(server: SFTPServer, password: String) async throws -> SFTPConnection {
        let key: NIOSSHPublicKey
        do {
            key = try NIOSSHPublicKey(openSSHPublicKey: server.trustedHostKey)
        } catch { throw SFTPError.invalidHostKey }
        let settings = SSHClientSettings(
            host: server.host,
            port: server.port,
            authenticationMethod: {
                .passwordBased(username: server.username, password: password)
            },
            hostKeyValidator: .trustedKeys([key])
        )
        let ssh = try await SSHClient.connect(to: settings)
        do {
            let sftp = try await ssh.openSFTP()
            do {
                let root = try SFTPPathPolicy.normalize(
                    try await sftp.getRealPath(atPath: server.rootPath)
                )
                return SFTPConnection(
                    ssh: ssh, sftp: sftp, canonicalRoot: root,
                    declaredRoot: server.rootPath
                )
            } catch {
                try? await sftp.close()
                throw error
            }
        } catch {
            try? await ssh.close()
            throw error
        }
    }

    func close() async {
        try? await sftp.close()
        try? await ssh.close()
    }

    private func resolved(_ path: String) async throws -> String {
        let normalized = try SFTPPathPolicy.normalize(path)
        guard SFTPPathPolicy.inside(normalized, root: declaredRoot) else {
            throw SFTPError.escapedRoot
        }
        let real = try SFTPPathPolicy.normalize(
            try await sftp.getRealPath(atPath: normalized)
        )
        guard SFTPPathPolicy.inside(real, root: canonicalRoot) else {
            throw SFTPError.escapedRoot
        }
        return real
    }

    func list(directory: String) async throws -> [SFTPEntry] {
        let realDirectory = try await resolved(directory)
        let batches = try await sftp.listDirectory(atPath: realDirectory)
        var entries: [SFTPEntry] = []
        for component in batches.flatMap(\.components) {
            let name = component.filename
            guard let path = try? SFTPPathPolicy.child(
                name, in: directory, root: declaredRoot
            ) else { continue }

            let type = component.attributes.permissions.map { $0 & 0o170000 }
            if type == 0o120000 || component.longname.hasPrefix("l") {
                // Never follow a link outside the configured server root.
                continue
            }
            let directoryMode = type == 0o040000 || component.longname.hasPrefix("d")
            let fileMode = type == 0o100000 || component.longname.hasPrefix("-")
            guard directoryMode || fileMode else { continue }
            entries.append(SFTPEntry(
                name: name, path: path, isDirectory: directoryMode,
                size: component.attributes.size.flatMap(Int64.init(exactly:))
            ))
        }
        return entries.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Create a subdirectory inside the configured SSH root.
    func createDirectory(named name: String, in directory: String) async throws {
        let parent = try await resolved(directory)
        let destination = try SFTPPathPolicy.child(
            name, in: parent, root: canonicalRoot
        )
        try await sftp.createDirectory(atPath: destination)
    }

    /// Remove a file or an EMPTY directory only. SFTP rmdir deliberately
    /// refuses nonempty folders; there is no recursive delete here.
    func remove(_ entry: SFTPEntry) async throws {
        let real = try await resolved(entry.path)
        guard real != canonicalRoot else { throw SFTPError.escapedRoot }
        if entry.isDirectory {
            try await sftp.rmdir(at: real)
        } else {
            try await sftp.remove(at: real)
        }
    }

    /// Upload the given file with SSH_FXF_EXCL so compliant SFTP servers
    /// refuse to overwrite a preexisting file. No full-file RAM buffering.
    func upload(localURL: URL, in directory: String) async throws {
        let scoped = localURL.startAccessingSecurityScopedResource()
        defer { if scoped { localURL.stopAccessingSecurityScopedResource() } }
        var isDirectory: ObjCBool = false
        guard localURL.isFileURL,
              FileManager.default.fileExists(atPath: localURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { throw SFTPError.unsupportedEntry }

        let parent = try await resolved(directory)
        let destination = try SFTPPathPolicy.child(
            localURL.lastPathComponent, in: parent, root: canonicalRoot
        )
        let source = try FileHandle(forReadingFrom: localURL)
        defer { try? source.close() }
        let remote = try await sftp.openFile(
            filePath: destination, flags: [.write, .create, .forceCreate]
        )
        do {
            var offset: UInt64 = 0
            while let bytes = try source.read(upToCount: 32_768), !bytes.isEmpty {
                try Task.checkCancellation()
                var buffer = ByteBufferAllocator().buffer(capacity: bytes.count)
                buffer.writeBytes(bytes)
                try await remote.write(buffer, at: offset)
                offset += UInt64(bytes.count)
            }
            try await remote.close()
        } catch {
            // Do not automatically delete: a remote concurrent writer could
            // have replaced the partial file since we created it.
            try? await remote.close()
            throw error
        }
    }

    /// Open a random-access handle for AVFoundation's resource loader.
    /// Only real paths inside the configured canonical root are permitted.
    func openReadStream(_ entry: SFTPEntry) async throws -> SFTPReadHandle {
        guard !entry.isDirectory else { throw SFTPError.unsupportedEntry }
        let path = try await resolved(entry.path)
        let file = try await sftp.openFile(filePath: path, flags: .read)
        do {
            let attributes = try await file.readAttributes()
            guard let size = attributes.size,
                  size > 0, size <= UInt64(Int64.max) else {
                throw SFTPError.incompleteTransfer
            }
            return SFTPReadHandle(connection: self, file: file, size: Int64(size))
        } catch {
            try? await file.close()
            throw error
        }
    }

    /// Read bounded chunks directly into an app-private temporary file.
    /// No entire video is held in memory, and cancellation checks run
    /// between SFTP reads. The caller must move or remove the temp file.
    func download(_ entry: SFTPEntry) async throws -> URL {
        guard !entry.isDirectory else { throw SFTPError.unsupportedEntry }
        let path = try await resolved(entry.path)
        let remote = try await sftp.openFile(filePath: path, flags: .read)
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("vidrane-sftp-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: temporary.path, contents: nil)
        do {
            let output = try FileHandle(forWritingTo: temporary)
            defer { try? output.close() }
            let attributes = try await remote.readAttributes()
            var offset: UInt64 = 0
            while true {
                try Task.checkCancellation()
                let chunk = try await remote.read(from: offset, length: 32_768)
                guard chunk.readableBytes > 0 else { break }
                try output.write(contentsOf: Data(chunk.readableBytesView))
                offset += UInt64(chunk.readableBytes)
                if let expected = attributes.size, offset >= expected { break }
            }
            if let expected = attributes.size, offset != expected {
                throw SFTPError.incompleteTransfer
            }
            try await remote.close()
            return temporary
        } catch {
            try? await remote.close()
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}


/// An open, verified SFTP file owned by one playback session. All reads
/// are bounded; never load a full movie into the app's memory.
final class SFTPReadHandle {
    let size: Int64
    private let connection: SFTPConnection
    private let file: Citadel.SFTPFile

    init(connection: SFTPConnection, file: Citadel.SFTPFile, size: Int64) {
        self.connection = connection
        self.file = file
        self.size = size
    }

    func read(offset: Int64, count: Int) async throws -> Data {
        guard offset >= 0, offset < size, count > 0,
              count <= 64 * 1024, Int64(count) <= size - offset else {
            throw SFTPError.invalidPath
        }
        var output = Data()
        output.reserveCapacity(count)
        while output.count < count {
            try Task.checkCancellation()
            // Servers may respond with less than the requested length.
            // The conservative block size also works with SFTP daemons
            // that cap individual reads at 32 KiB.
            let block = min(32_768, count - output.count)
            let response = try await file.read(
                from: UInt64(offset) + UInt64(output.count),
                length: UInt32(block)
            )
            try Task.checkCancellation()
            guard response.readableBytes > 0,
                  response.readableBytes <= block else {
                throw SFTPError.incompleteTransfer
            }
            output.append(contentsOf: response.readableBytesView)
        }
        return output
    }

    func close() async {
        try? await file.close()
        await connection.close()
    }
}
