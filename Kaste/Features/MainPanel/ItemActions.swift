import AppKit
import UniformTypeIdentifiers

enum ItemActions {

    // MARK: - Drag

    /// Provider for dragging a card OUT of Kaste — into Finder, Mail,
    /// Slack, etc. Only file and image kinds have anything meaningful to
    /// hand off; text/URL/color cards return nil so `.onDrag` yields an
    /// empty provider and the drag simply doesn't take.
    static func makeExternalDragProvider(for item: ClipItem) -> NSItemProvider? {
        switch item.kind {
        case .file:
            guard let url = fileURLs(for: item).first else { return nil }
            return NSItemProvider(object: url as NSURL)
        case .image:
            guard let url = ensureImageTempFile(for: item) else { return nil }
            return NSItemProvider(object: url as NSURL)
        default:
            return nil
        }
    }

    // MARK: - Reveal in Finder

    static func revealInFinder(_ item: ClipItem) {
        switch item.kind {
        case .file:
            let urls = fileURLs(for: item)
            guard !urls.isEmpty else { return }
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        case .image:
            // Materialize the cached PNG so the user can grab it from Finder.
            if let url = ensureImageTempFile(for: item) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        default:
            // Nothing to reveal for text / rtf / url / color.
            NSSound.beep()
        }
    }

    // MARK: - Helpers

    private static func fileURLs(for item: ClipItem) -> [URL] {
        (item.filePaths ?? []).compactMap { URL(fileURLWithPath: $0) }
    }

    static let tempDir: URL = {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kaste-Previews", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            NSLog("Kaste: preview tempDir create failed: \(error)")
        }
        return dir
    }()

    /// Called from AppDelegate at launch. Delete cached PNGs older than 7d
    /// so the folder doesn't grow unbounded.
    static func pruneOldTempFiles() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        for url in entries {
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if mtime < cutoff {
                do { try fm.removeItem(at: url) }
                catch { NSLog("Kaste: temp prune failed for \(url.lastPathComponent): \(error)") }
            }
        }
    }

    static func ensureImageTempFile(for item: ClipItem) -> URL? {
        guard let data = item.imageData else { return nil }
        let url = tempDir.appendingPathComponent("\(item.id.uuidString).png")
        if !FileManager.default.fileExists(atPath: url.path) {
            do { try data.write(to: url) }
            catch { NSLog("Kaste: preview tempfile write failed: \(error)") }
        }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

}
