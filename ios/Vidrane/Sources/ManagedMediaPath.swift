import Foundation

/// Local filesystem policy, independent of SwiftUI and media engines.
/// Lexical identifiers remain stable even after a move; operations on existing
/// items separately validate the real path and reject symlink traversal.
enum ManagedMediaPath {
    static func relative(_ url: URL, to root: URL) -> String? {
        guard url.isFileURL, root.isFileURL else { return nil }
        let base = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        let prefix = base.hasSuffix("/") ? base : base + "/"
        guard path.hasPrefix(prefix) else { return nil }
        let result = String(path.dropFirst(prefix.count))
        return result.isEmpty ? nil : result
    }

    static func validName(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.hasPrefix("."),
              !name.contains("/"), !name.contains("\\"),
              !name.contains("\0") else { return nil }
        return name
    }

    static func contains(_ key: String, under parent: String) -> Bool {
        !parent.isEmpty && (key == parent || key.hasPrefix(parent + "/"))
    }

    static func rebased(_ key: String, from old: String, to new: String) -> String {
        guard contains(key, under: old) else { return key }
        return new + String(key.dropFirst(old.count))
    }

    static func isSafeExistingItem(_ url: URL, in root: URL, allowRoot: Bool = false) -> Bool {
        guard url.isFileURL, root.isFileURL else { return false }
        let base = root.standardizedFileURL
        let item = url.standardizedFileURL
        let rootValues = try? base.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootValues?.isDirectory == true, rootValues?.isSymbolicLink != true else { return false }
        if item.path == base.path { return allowRoot }
        guard let key = relative(item, to: base) else { return false }

        // Reject symlinks at every component, including links that happen to
        // point back into Media. This is a defense for normal local operations,
        // not a guarantee against concurrent external filesystem mutation.
        var cursor = base
        for component in key.split(separator: "/") {
            cursor.appendPathComponent(String(component))
            guard let values = try? cursor.resourceValues(forKeys: [.isSymbolicLinkKey]),
                  values.isSymbolicLink == false else { return false }
        }
        guard FileManager.default.fileExists(atPath: item.path) else { return false }
        return relative(item.resolvingSymlinksInPath(), to: base.resolvingSymlinksInPath()) == key
    }
}
