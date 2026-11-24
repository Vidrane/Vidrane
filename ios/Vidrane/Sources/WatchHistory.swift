import Foundation
import SwiftUI

struct WatchCheckpoint: Codable {
    var seconds: Double
    var duration: Double
    var updatedAt: Date

    var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, seconds / duration))
    }
}

/// Watch history is keyed by a path relative to Documents/Media. Existing
/// first-stage flat filename keys remain unchanged after this migration.
@MainActor
final class WatchHistory: ObservableObject {
    static let shared = WatchHistory()

    @Published private(set) var checkpoints: [String: WatchCheckpoint] = [:]

    private let fileURL: URL
    private let mediaRoot: URL

    private init() {
        let documents = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        )[0]
        mediaRoot = documents.appendingPathComponent("Media", isDirectory: true)
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        fileURL = directory.appendingPathComponent("watch-history.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(
               [String: WatchCheckpoint].self, from: data
           ) {
            checkpoints = decoded
        }
    }

    private func key(for url: URL) -> String? {
        ManagedMediaPath.relative(url, to: mediaRoot)
    }

    func checkpoint(for url: URL) -> WatchCheckpoint? {
        guard let key = key(for: url),
              let item = checkpoints[key],
              vidrane_resume_position(item.seconds, item.duration) > 0 else {
            return nil
        }
        return item
    }

    func record(url: URL, seconds: Double, duration: Double) {
        guard let key = key(for: url),
              seconds.isFinite, duration.isFinite, duration >= 30 else { return }
        if vidrane_playback_finished(seconds, duration) {
            remove(url: url)
            return
        }
        guard vidrane_resume_position(seconds, duration) > 0 else { return }
        checkpoints[key] = WatchCheckpoint(
            seconds: seconds, duration: duration, updatedAt: Date()
        )
        persist()
    }

    func remove(url: URL) {
        guard let key = key(for: url) else { return }
        if checkpoints.removeValue(forKey: key) != nil { persist() }
    }

    func removeTree(url: URL) {
        guard let key = key(for: url) else { return }
        let before = checkpoints.count
        checkpoints = checkpoints.filter {
            !ManagedMediaPath.contains($0.key, under: key)
        }
        if checkpoints.count != before { persist() }
    }

    /// Moves entire folders' checkpoints without confusing same-name media
    /// residing in different directories.
    func rebase(from source: URL, to destination: URL) {
        guard let oldKey = key(for: source), let newKey = key(for: destination),
              oldKey != newKey else { return }
        var updated: [String: WatchCheckpoint] = [:]
        for (key, checkpoint) in checkpoints {
            updated[ManagedMediaPath.rebased(key, from: oldKey, to: newKey)] = checkpoint
        }
        checkpoints = updated
        persist()
    }

    func clearAll() {
        checkpoints.removeAll()
        persist()
    }

    private func persist() {
        do {
            let encoded = try JSONEncoder().encode(checkpoints)
            try encoded.write(to: fileURL, options: [.atomic])
        } catch {
            NSLog("Vidrane: could not save local watch history: %@", String(describing: error))
        }
    }
}
