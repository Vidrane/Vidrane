import Foundation
import SwiftUI

enum VidraneMediaKind: Int {
    case unknown = 0, video, audio, subtitle, playlist, image

    init(filename: String) {
        let raw = filename.withCString { Int(vidrane_media_kind($0)) }
        self = VidraneMediaKind(rawValue: raw) ?? .unknown
    }

    var symbol: String {
        switch self {
        case .video: return "film"
        case .audio: return "music.note"
        case .subtitle: return "captions.bubble"
        case .playlist: return "list.bullet"
        case .image: return "photo"
        case .unknown: return "doc"
        }
    }

    var playable: Bool { self == .video || self == .audio }
}

struct LocalMedia: Identifiable, Hashable {
    let url: URL
    let relativePath: String
    let kind: VidraneMediaKind
    let isDirectory: Bool
    let bytes: Int64
    let modified: Date?

    var id: String { relativePath }
    var name: String { url.lastPathComponent }
    var symbol: String { isDirectory ? "folder.fill" : kind.symbol }
}

struct StoredPlaylist: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    /// Relative to Documents/Media, for stable nested-folder references.
    /// Flat names from older releases remain identical.
    var files: [String] = []
}

struct PlaybackRequest: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let webDAVStream: WebDAVRangeStream?
    let sftpStream: SFTPRangeStream?
    let remoteRelay: MediaLoopbackRelay?

    init(
        url: URL, title: String,
        webDAVStream: WebDAVRangeStream? = nil,
        sftpStream: SFTPRangeStream? = nil,
        remoteRelay: MediaLoopbackRelay? = nil
    ) {
        self.url = url
        self.title = title
        self.webDAVStream = webDAVStream
        self.sftpStream = sftpStream
        self.remoteRelay = remoteRelay
    }
}

enum LocalFileError: LocalizedError {
    case invalidName
    case invalidLocation
    case targetExists
    case sameFolder

    var errorDescription: String? {
        switch self {
        case .invalidName: return "Недопустимое имя. Уберите разделители пути и скрытые имена."
        case .invalidLocation: return "Операция разрешена только внутри медиатеки Vidrane."
        case .targetExists: return "Файл или папка с таким названием уже существует."
        case .sameFolder: return "Нельзя поместить папку внутрь самой себя."
        }
    }
}

@MainActor
final class MediaLibrary: ObservableObject {
    @Published private(set) var files: [LocalMedia] = []
    @Published private(set) var playlists: [StoredPlaylist] = []
    @Published var playback: PlaybackRequest?
    @Published var errorMessage: String?

    private let fm = FileManager.default

    private var documents: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    var rootDirectory: URL {
        documents.appendingPathComponent("Media", isDirectory: true)
    }

    private var playlistsFile: URL {
        documents.appendingPathComponent("playlists.json")
    }

    init() {
        do {
            try fm.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        } catch {
            errorMessage = error.localizedDescription
        }
        restorePlaylists()
        refreshFiles()
    }

    /// Resolve only lexical children of Media; never permit operations on
    /// an arbitrary file selected outside the sandbox.
    func relativePath(for url: URL) -> String? {
        ManagedMediaPath.relative(url, to: rootDirectory)
    }

    func isValidFolder(_ folder: URL) -> Bool {
        let root = rootDirectory.standardizedFileURL
        let candidate = folder.standardizedFileURL
        guard ManagedMediaPath.isSafeExistingItem(candidate, in: root, allowRoot: true),
              let values = try? candidate.resourceValues(forKeys: [.isDirectoryKey]),
              values.isDirectory == true else {
            return false
        }
        return true
    }

    func entries(in folder: URL) -> [LocalMedia] {
        guard isValidFolder(folder) else { return [] }
        return files.filter {
            $0.url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL
        }
    }

    var folders: [LocalMedia] { files.filter(\.isDirectory) }

    func refreshFiles() {
        do {
            guard let enumerator = fm.enumerator(
                at: rootDirectory,
                includingPropertiesForKeys: [
                    .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey,
                    .contentModificationDateKey
                ],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                files = []
                return
            }
            var found: [LocalMedia] = []
            while let url = enumerator.nextObject() as? URL {
                guard let relative = relativePath(for: url) else { continue }
                let values = try? url.resourceValues(forKeys: [
                    .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey,
                    .contentModificationDateKey
                ])
                if values?.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    continue
                }
                found.append(LocalMedia(
                    url: url,
                    relativePath: relative,
                    kind: VidraneMediaKind(filename: url.lastPathComponent),
                    isDirectory: values?.isDirectory == true,
                    bytes: Int64(values?.fileSize ?? 0),
                    modified: values?.contentModificationDate
                ))
            }
            files = found.sorted {
                $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
            }
        } catch {
            errorMessage = "Не удалось прочитать медиатеку: \(error.localizedDescription)"
        }
    }

    private func validName(_ raw: String) -> String? {
        ManagedMediaPath.validName(raw)
    }

    private func destination(for name: String, in folder: URL, unique: Bool) throws -> URL {
        guard isValidFolder(folder) else { throw LocalFileError.invalidLocation }
        guard let safe = validName(name) else { throw LocalFileError.invalidName }
        let target = folder.appendingPathComponent(safe)
        if !fm.fileExists(atPath: target.path) { return target }
        guard unique else { throw LocalFileError.targetExists }
        let stem = (safe as NSString).deletingPathExtension
        let ext = (safe as NSString).pathExtension
        for number in 1...10_000 {
            let candidateName = "\(stem) (\(number))" + (ext.isEmpty ? "" : ".\(ext)")
            let candidate = folder.appendingPathComponent(candidateName)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
        }
        throw LocalFileError.targetExists
    }

    func importFiles(_ urls: [URL], to folder: URL? = nil) {
        let folder = folder ?? rootDirectory
        guard isValidFolder(folder) else {
            errorMessage = LocalFileError.invalidLocation.localizedDescription
            return
        }
        for source in urls {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            do {
                let target = try destination(
                    for: source.lastPathComponent, in: folder, unique: true
                )
                try fm.copyItem(at: source, to: target)
            } catch {
                errorMessage = "Ошибка импорта \(source.lastPathComponent): \(error.localizedDescription)"
            }
        }
        refreshFiles()
    }

    func createFolder(named name: String, in folder: URL) {
        do {
            let target = try destination(for: name, in: folder, unique: false)
            try fm.createDirectory(at: target, withIntermediateDirectories: false)
            refreshFiles()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func managedSource(_ file: LocalMedia) throws -> URL {
        guard ManagedMediaPath.isSafeExistingItem(file.url, in: rootDirectory) else {
            throw LocalFileError.invalidLocation
        }
        return file.url
    }

    /// After a move/rename, migrate playlist and resume keys for an entire
    /// subtree; legacy flat entries are valid relative paths.
    private func rebaseReferences(from old: URL, to new: URL) {
        guard let oldKey = relativePath(for: old),
              let newKey = relativePath(for: new) else { return }
        for index in playlists.indices {
            playlists[index].files = playlists[index].files.map { value in
                ManagedMediaPath.rebased(value, from: oldKey, to: newKey)
            }
        }
        savePlaylists()
        WatchHistory.shared.rebase(from: old, to: new)
    }

    func delete(_ file: LocalMedia) {
        do {
            _ = try managedSource(file)
            try fm.removeItem(at: file.url)
            for index in playlists.indices {
                playlists[index].files.removeAll {
                    ManagedMediaPath.contains($0, under: file.id)
                }
            }
            savePlaylists()
            WatchHistory.shared.removeTree(url: file.url)
            refreshFiles()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rename(_ file: LocalMedia, to enteredName: String) {
        do {
            _ = try managedSource(file)
            guard let name = validName(enteredName) else {
                throw LocalFileError.invalidName
            }
            if name == file.name { return }
            let folder = file.url.deletingLastPathComponent()
            let target = try destination(for: name, in: folder, unique: false)
            try fm.moveItem(at: file.url, to: target)
            rebaseReferences(from: file.url, to: target)
            refreshFiles()
        } catch {
            errorMessage = "Переименование: \(error.localizedDescription)"
        }
    }

    func relocate(_ file: LocalMedia, to folder: URL, copy: Bool) {
        do {
            let source = try managedSource(file)
            guard isValidFolder(folder) else { throw LocalFileError.invalidLocation }
            if file.isDirectory {
                let original = source.standardizedFileURL.path
                let targetFolder = folder.standardizedFileURL.path
                if targetFolder == original || targetFolder.hasPrefix(original + "/") {
                    throw LocalFileError.sameFolder
                }
            }
            if source.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL &&
                !copy {
                return
            }
            let target = try destination(for: file.name, in: folder, unique: copy)
            if copy {
                try fm.copyItem(at: source, to: target)
            } else {
                try fm.moveItem(at: source, to: target)
                rebaseReferences(from: source, to: target)
            }
            refreshFiles()
        } catch {
            errorMessage = "\(copy ? "Копирование" : "Перемещение"): \(error.localizedDescription)"
        }
    }

    /// Takes ownership of an already downloaded local temporary file.
    func importRemoteFile(at temporary: URL, filename: String) throws -> LocalMedia {
        let safeName = (filename as NSString).lastPathComponent
        let name = validName(safeName) ?? "remote-\(UUID().uuidString)"
        let target = try destination(for: name, in: rootDirectory, unique: true)
        try fm.moveItem(at: temporary, to: target)
        refreshFiles()
        guard let relative = relativePath(for: target),
              let file = files.first(where: { $0.id == relative }) else {
            throw CocoaError(.fileReadUnknown)
        }
        return file
    }

    func play(_ file: LocalMedia) {
        guard !file.isDirectory, file.kind.playable else {
            errorMessage = "Для этого типа файла пока не реализован просмотр."
            return
        }
        playback = PlaybackRequest(url: file.url, title: file.name)
    }

    /// Start a verified byte-range WebDAV stream without importing the file.
    /// AVFoundation is used for this synthetic asset, not libmpv.
    func playWebDAV(_ source: WebDAVRangeStream, title: String) {
        playback = PlaybackRequest(
            url: source.asset.url,
            title: title,
            webDAVStream: source
        )
    }

    /// Play an SFTP media file using on-demand SSH range reads.
    /// The synthetic AVURLAsset URL never carries server credentials.
    func playSFTP(_ source: SFTPRangeStream, title: String) {
        playback = PlaybackRequest(
            url: source.asset.url,
            title: title,
            sftpStream: source
        )
    }

    func playRemoteMPV(_ relay: MediaLoopbackRelay, title: String) {
        playback = PlaybackRequest(
            url: relay.url, title: title, remoteRelay: relay
        )
    }

    func playRemote(_ address: String) {
        guard let url = verifiedURL(address) else { return }
        playback = PlaybackRequest(
            url: url,
            title: url.lastPathComponent.isEmpty ? url.host ?? "Поток" : url.lastPathComponent
        )
    }

    private func verifiedURL(_ address: String) -> URL? {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https",
              url.host != nil, url.user == nil, url.password == nil else {
            errorMessage = "Поддерживаются только HTTPS-ссылки без пароля внутри адреса."
            return nil
        }
        return url
    }

    func download(_ address: String) {
        guard let url = verifiedURL(address) else { return }
        do {
            try TransferCenter.shared.enqueue(
                url: url,
                filename: url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent,
                library: self
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createPlaylist(name: String) {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        playlists.append(StoredPlaylist(name: value))
        savePlaylists()
    }

    func deletePlaylist(id: UUID) {
        playlists.removeAll { $0.id == id }
        savePlaylists()
    }

    func files(in playlist: StoredPlaylist) -> [LocalMedia] {
        playlist.files.compactMap { identifier in
            files.first { $0.id == identifier && !$0.isDirectory }
        }
    }

    func add(_ file: LocalMedia, to id: UUID) {
        guard !file.isDirectory,
              let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        guard !playlists[index].files.contains(file.id) else { return }
        playlists[index].files.append(file.id)
        savePlaylists()
    }

    func remove(_ file: LocalMedia, from id: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].files.removeAll { $0 == file.id }
        savePlaylists()
    }

    private func restorePlaylists() {
        guard let data = try? Data(contentsOf: playlistsFile) else { return }
        playlists = (try? JSONDecoder().decode([StoredPlaylist].self, from: data)) ?? []
    }

    private func savePlaylists() {
        do {
            let data = try JSONEncoder().encode(playlists)
            try data.write(to: playlistsFile, options: .atomic)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
