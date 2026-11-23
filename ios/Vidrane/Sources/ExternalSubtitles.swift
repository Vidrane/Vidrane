import Foundation
import SwiftUI

struct ExternalSubtitleCue: Decodable {
    let startMs: UInt64
    let endMs: UInt64
    let text: String

    enum CodingKeys: String, CodingKey {
        case startMs = "start_ms"
        case endMs = "end_ms"
        case text
    }
}

/// Swift file-access layer for the shared Rust SRT/WebVTT parser.
/// Only UTF-8 text is supported at this stage. No subtitles leave the device.
@MainActor
final class ExternalSubtitles: ObservableObject {
    @Published private(set) var cues: [ExternalSubtitleCue] = []
    @Published private(set) var filename: String?
    @Published var enabled = true
    @Published var errorMessage: String?

    func clear() {
        cues = []
        filename = nil
        errorMessage = nil
    }

    func cue(at seconds: Double) -> String? {
        guard enabled, seconds.isFinite, seconds >= 0 else { return nil }
        let milliseconds = UInt64(min(seconds * 1000, Double(UInt64.max / 2)))
        // The parsed cues are ordered by starting time. Binary search for the
        // last cue that starts before the current timestamp.
        var lower = 0
        var upper = cues.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if cues[middle].startMs <= milliseconds {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        guard lower > 0 else { return nil }
        // Also support short overlapping cues from a preceding entry.
        for index in stride(from: lower - 1, through: max(0, lower - 4), by: -1) {
            let candidate = cues[index]
            if candidate.startMs <= milliseconds && milliseconds < candidate.endMs {
                return candidate.text
            }
        }
        return nil
    }

    func loadSidecar(for mediaURL: URL) {
        clear()
        guard mediaURL.isFileURL else { return }
        let folder = mediaURL.deletingLastPathComponent()
        let stem = mediaURL.deletingPathExtension().lastPathComponent.lowercased()
        guard let siblings = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return }
        let candidates = siblings.filter { url in
            let ext = url.pathExtension.lowercased()
            let basename = url.lastPathComponent.lowercased()
            return (ext == "srt" || ext == "vtt")
                && (basename == stem + "." + ext || basename.hasPrefix(stem + "."))
        }.sorted { lhs, rhs in
            let a = lhs.lastPathComponent.lowercased()
            let b = rhs.lastPathComponent.lowercased()
            let aExact = a == stem + ".srt" || a == stem + ".vtt"
            let bExact = b == stem + ".srt" || b == stem + ".vtt"
            return aExact == bExact ? a < b : aExact
        }
        for candidate in candidates {
            if load(url: candidate, displayErrors: false) { return }
        }
    }

    @discardableResult
    func load(url: URL, displayErrors: Bool = true) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard ext == "srt" || ext == "vtt" else {
            if displayErrors { errorMessage = "Поддерживаются только файлы .srt и .vtt." }
            return false
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty && data.count <= 8 * 1024 * 1024 else {
                if displayErrors { errorMessage = "Файл субтитров пуст или больше 8 МБ." }
                return false
            }
            let decoded: [ExternalSubtitleCue]? = data.withUnsafeBytes { rawBytes in
                guard let pointer = rawBytes.bindMemory(to: UInt8.self).baseAddress,
                      let result = vidrane_subtitles_parse_json(pointer, UInt(data.count)) else {
                    return nil
                }
                defer { vidrane_subtitles_free_json(result) }
                let json = Data(String(cString: result).utf8)
                return try? JSONDecoder().decode([ExternalSubtitleCue].self, from: json)
            }
            guard let decoded, !decoded.isEmpty else {
                if displayErrors {
                    errorMessage = "Не удалось прочитать UTF-8 субтитры или в файле нет корректных реплик."
                }
                return false
            }
            cues = decoded
            filename = url.lastPathComponent
            enabled = true
            errorMessage = nil
            return true
        } catch {
            if displayErrors { errorMessage = "Ошибка чтения субтитров: \(error.localizedDescription)" }
            return false
        }
    }
}
