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
    let kind: VidraneMediaKind
    let bytes: Int64
    let modified: Date?

    var id: String { url.lastPathComponent }
    var name: String { url.lastPathComponent }
}

struct StoredPlaylist: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var files: [String] = []
}

struct PlaybackRequest: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
}

struct DownloadItem: Identifiable {
    let id = UUID()
    let name: String
    var status: String
}

@MainActor
final class MediaLibrary: ObservableObject {
    @Published private(set) var files: [LocalMedia] = []
    @Published private(set) var playlists: [StoredPlaylist] = []
    @Published private(set) var downloads: [DownloadItem] = []
    @Published var playback: PlaybackRequest?
    @Published var errorMessage: String?

    private let fm = FileManager.default

    private var documents: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private var mediaDirectory: URL {
        documents.appendingPathComponent("Media", isDirectory: true)
    }
    private var playlistsFile: URL {
        documents.appendingPathComponent("playlists.json")
    }

    init() {
        do { try fm.createDirectory(at: mediaDirectory, withIntermediateDirectories: true) }
        catch { errorMessage = error.localizedDescription }
        restorePlaylists()
        refreshFiles()
    }

    func refreshFiles() {
        do {
            let urls = try fm.contentsOfDirectory(at: mediaDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            files = urls.filter { !$0.hasDirectoryPath }
                .map { url -> LocalMedia in
                    let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                    return LocalMedia(
                        url: url,
                        kind: VidraneMediaKind(filename: url.lastPathComponent),
                        bytes: Int64(values?.fileSize ?? 0),
                        modified: values?.contentModificationDate
                    )
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch {
            errorMessage = "Не удалось прочитать папку: \(error.localizedDescription)"
        }
    }

    private func uniqueDestination(for name: String) -> URL {
        var destination = mediaDirectory.appendingPathComponent(name)
        guard fm.fileExists(atPath: destination.path) else { return destination }
        let original = (name as NSString).deletingPathExtension
        let suffix = (name as NSString).pathExtension
        let newName = original + "-" + String(UUID().uuidString.prefix(8)) + (suffix.isEmpty ? "" : "." + suffix)
        destination = mediaDirectory.appendingPathComponent(newName)
        return destination
    }

    func importFiles(_ urls: [URL]) {
        for source in urls {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            do {
                let destination = uniqueDestination(for: source.lastPathComponent)
                try fm.copyItem(at: source, to: destination)
            } catch {
                errorMessage = "Ошибка импорта \(source.lastPathComponent): \(error.localizedDescription)"
            }
        }
        refreshFiles()
    }

    func delete(_ file: LocalMedia) {
        do {
            try fm.removeItem(at: file.url)
            WatchHistory.shared.remove(url: file.url)
            for index in playlists.indices { playlists[index].files.removeAll { $0 == file.id } }
            savePlaylists()
            refreshFiles()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Renames a file without changing its directory and keeps playlist IDs in sync.
    func rename(_ file: LocalMedia, to enteredName: String) {
        let name = enteredName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..",
              !name.hasPrefix("."), !name.contains("/"), !name.contains("\\") else {
            errorMessage = "Недопустимое имя файла."
            return
        }
        guard file.url.deletingLastPathComponent().standardizedFileURL == mediaDirectory.standardizedFileURL else {
            errorMessage = "Переименование доступно только для локальных файлов."
            return
        }
        guard name != file.name else { return }
        let destination = mediaDirectory.appendingPathComponent(name)
        guard !fm.fileExists(atPath: destination.path) else {
            errorMessage = "Файл с таким именем уже существует."
            return
        }
        do {
            try fm.moveItem(at: file.url, to: destination)
            WatchHistory.shared.rename(from: file.url, to: destination)
            for index in playlists.indices {
                playlists[index].files = playlists[index].files.map { $0 == file.id ? name : $0 }
            }
            savePlaylists()
            refreshFiles()
        } catch {
            errorMessage = "Переименование не удалось: \(error.localizedDescription)"
        }
    }

    /// Takes ownership of a finished temporary download and adds it to the
    /// local media library. WebDAV paths never become local filesystem paths.
    func importRemoteFile(at temporary: URL, filename: String) throws -> LocalMedia {
        let safeName = (filename as NSString).lastPathComponent
        let name = safeName.isEmpty || safeName == "." || safeName == ".."
            ? "remote-\(UUID().uuidString)" : safeName
        let destination = uniqueDestination(for: name)
        try fm.moveItem(at: temporary, to: destination)
        refreshFiles()
        guard let file = files.first(where: { $0.url == destination }) else {
            throw CocoaError(.fileReadUnknown)
        }
        return file
    }

    func play(_ file: LocalMedia) {
        guard file.kind.playable else {
            errorMessage = "Для этого типа файла пока не реализован просмотр."
            return
        }
        playback = PlaybackRequest(url: file.url, title: file.name)
    }

    func playRemote(_ address: String) {
        guard let url = verifiedURL(address) else { return }
        playback = PlaybackRequest(url: url, title: url.lastPathComponent.isEmpty ? url.host ?? "Поток" : url.lastPathComponent)
    }

    private func verifiedURL(_ address: String) -> URL? {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", url.host != nil else {
            errorMessage = "На первом этапе поддерживаются прямые HTTPS-ссылки."
            return nil
        }
        return url
    }

    func download(_ address: String) {
        guard let url = verifiedURL(address) else { return }
        let record = DownloadItem(name: url.lastPathComponent.isEmpty ? "media" : url.lastPathComponent, status: "Загрузка")
        downloads.insert(record, at: 0)
        Task {
            do {
                let (temporary, response) = try await URLSession.shared.download(from: url)
                if let response = response as? HTTPURLResponse, !(200...299).contains(response.statusCode) {
                    throw URLError(.badServerResponse)
                }
                let destination = uniqueDestination(for: record.name)
                try fm.moveItem(at: temporary, to: destination)
                updateDownload(id: record.id, status: "Готово")
                refreshFiles()
            } catch {
                updateDownload(id: record.id, status: "Ошибка")
                errorMessage = "Не удалось скачать файл: \(error.localizedDescription)"
            }
        }
    }

    private func updateDownload(id: UUID, status: String) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        downloads[index].status = status
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
        playlist.files.compactMap { name in files.first { $0.id == name } }
    }

    func add(_ file: LocalMedia, to id: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
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
        } catch { errorMessage = error.localizedDescription }
    }
}
