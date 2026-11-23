import Citadel
import Foundation
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
