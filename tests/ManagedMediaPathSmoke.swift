import Foundation

@main
struct ManagedMediaPathSmoke {
    static func main() throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: temp) }
        let root = temp.appendingPathComponent("Media", isDirectory: true)
        let child = root.appendingPathComponent("Shows/Episode.mkv")
        let outside = temp.appendingPathComponent("MediaOther", isDirectory: true)
        try fm.createDirectory(at: child.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data([1]).write(to: child)
        let outsideFile = outside.appendingPathComponent("secret.mkv")
        try Data([2]).write(to: outsideFile)
        let link = root.appendingPathComponent("Linked")
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)

        precondition(ManagedMediaPath.relative(child, to: root) == "Shows/Episode.mkv")
        precondition(ManagedMediaPath.relative(outsideFile, to: root) == nil)
        precondition(ManagedMediaPath.relative(root, to: root) == nil)
        precondition(ManagedMediaPath.relative(URL(string: "https://example.org/movie")!, to: root) == nil)
        precondition(ManagedMediaPath.validName(" Episode.mkv ") == "Episode.mkv")
        for invalid in ["", ".", "..", ".hidden", "a/b", "a\\b", "a\0b"] {
            precondition(ManagedMediaPath.validName(invalid) == nil)
        }
        precondition(ManagedMediaPath.contains("Show/E01.mkv", under: "Show"))
        precondition(!ManagedMediaPath.contains("Showcase/E01.mkv", under: "Show"))
        precondition(ManagedMediaPath.rebased("Show/E01.mkv", from: "Show", to: "New") == "New/E01.mkv")
        precondition(ManagedMediaPath.rebased("Showcase/E01.mkv", from: "Show", to: "New") == "Showcase/E01.mkv")
        precondition(ManagedMediaPath.isSafeExistingItem(child, in: root))
        precondition(ManagedMediaPath.isSafeExistingItem(root, in: root, allowRoot: true))
        precondition(!ManagedMediaPath.isSafeExistingItem(root, in: root))
        precondition(!ManagedMediaPath.isSafeExistingItem(outsideFile, in: root))
        precondition(!ManagedMediaPath.isSafeExistingItem(link, in: root))
        precondition(!ManagedMediaPath.isSafeExistingItem(link.appendingPathComponent("secret.mkv"), in: root))
        precondition(!ManagedMediaPath.isSafeExistingItem(root.appendingPathComponent("missing"), in: root))
        print("Vidrane Swift managed-path checks passed")
    }
}
