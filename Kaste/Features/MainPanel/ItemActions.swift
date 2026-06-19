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

    private static let tempDir: URL = {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kaste-Previews", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func ensureImageTempFile(for item: ClipItem) -> URL? {
        guard let data = item.imageData else { return nil }
        let url = tempDir.appendingPathComponent("\(item.id.uuidString).png")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url)
        }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func quickLook(urls: [URL]) {
        let p = Process()
        p.launchPath = "/usr/bin/qlmanage"
        p.arguments = ["-p"] + urls.map { $0.path }
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do { try p.run() } catch { NSWorkspace.shared.open(urls.first!) }
    }
}
