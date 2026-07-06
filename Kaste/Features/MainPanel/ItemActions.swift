import AppKit
import UniformTypeIdentifiers

enum ItemActions {

    // MARK: - Drag

    static func makeDragProvider(for item: ClipItem) -> NSItemProvider? {
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

    // MARK: - Quick Look

    static func preview(_ item: ClipItem) {
        switch item.kind {
        case .file:
            let urls = fileURLs(for: item)
            guard !urls.isEmpty else { return }
            // Use qlmanage for a proper QL window without depending on QLPreviewPanel state.
            quickLook(urls: urls)
        case .image:
            guard let url = ensureImageTempFile(for: item) else { return }
            quickLook(urls: [url])
        default:
            break
        }
    }

    // MARK: - Reveal in Finder

    static func revealInFinder(_ item: ClipItem) {
        let urls = fileURLs(for: item)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
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

    private static func ensureImageTempFile(for item: ClipItem) -> URL? {
        guard let data = item.imageData else { return nil }
        let url = tempDir.appendingPathComponent("\(item.id.uuidString).png")
        if !FileManager.default.fileExists(atPath: url.path) {
            do { try data.write(to: url) }
            catch { NSLog("Kaste: preview tempfile write failed: \(error)") }
        }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func quickLook(urls: [URL]) {
        guard !urls.isEmpty else { return }
        let p = Process()
        p.launchPath = "/usr/bin/qlmanage"
        p.arguments = ["-p"] + urls.map { $0.path }
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do {
            try p.run()
        } catch {
            NSLog("Kaste: qlmanage failed (\(error)); falling back to open")
            if let first = urls.first {
                NSWorkspace.shared.open(first)
            }
        }
    }
}
