import Foundation
import SwiftUI

/// Local-only playback checkpoints. No cloud account, analytics or server
/// requests are involved. Entries are keyed by the unique imported filename.
struct WatchCheckpoint: Codable {
    var seconds: Double
    var duration: Double
    var updatedAt: Date

    var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, seconds / duration))
    }
}

@MainActor
final class WatchHistory: ObservableObject {
    static let shared = WatchHistory()

    @Published private(set) var checkpoints: [String: WatchCheckpoint] = [:]

    private let fileURL: URL

    private init() {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        fileURL = directory.appendingPathComponent("watch-history.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(
               [String: WatchCheckpoint].self, from: data
           ) {
            checkpoints = decoded
        }
    }

    func checkpoint(for url: URL) -> WatchCheckpoint? {
        guard url.isFileURL,
              let item = checkpoints[url.lastPathComponent],
              vidrane_resume_position(item.seconds, item.duration) > 0 else {
            return nil
        }
        return item
    }

    /// Called periodically and when the player is dismissed.
    /// Unknown durations and streams never create a local checkpoint.
    func record(url: URL, seconds: Double, duration: Double) {
        guard url.isFileURL, seconds.isFinite, duration.isFinite, duration >= 30 else {
            return
        }
        if vidrane_playback_finished(seconds, duration) {
            remove(url: url)
            return
        }
        guard vidrane_resume_position(seconds, duration) > 0 else { return }
        let key = url.lastPathComponent
        checkpoints[key] = WatchCheckpoint(
            seconds: seconds, duration: duration, updatedAt: Date()
        )
        persist()
    }

    func remove(url: URL) {
        guard url.isFileURL else { return }
        if checkpoints.removeValue(forKey: url.lastPathComponent) != nil {
            persist()
        }
    }

    func rename(from source: URL, to destination: URL) {
        guard source.isFileURL, destination.isFileURL,
              source.lastPathComponent != destination.lastPathComponent,
              let item = checkpoints.removeValue(forKey: source.lastPathComponent) else {
            return
        }
        checkpoints[destination.lastPathComponent] = item
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
            // Keep in-memory checkpoints if the disk is unavailable.
            NSLog("Vidrane: could not save local watch history: %@", String(describing: error))
        }
    }
}
