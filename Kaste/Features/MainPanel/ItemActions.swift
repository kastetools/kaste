import AppKit
import UniformTypeIdentifiers

enum ItemActions {

    /// Custom UTI used exclusively for intra-panel drag-reorder. External
    /// apps ignore this identifier, so a card dragged to Finder still
    /// resolves via the file-URL representation below without triggering
    /// our own reorder drop.
    static let internalUUIDType = "app.kaste.internal.clipitem-uuid"

    // MARK: - Drag

    static func makeDragProvider(for item: ClipItem) -> NSItemProvider? {
        let provider = NSItemProvider()
        var registeredAny = false

        // External representation — file/image types can be dragged into
        // Finder, Mail, etc. as an actual file.
        switch item.kind {
        case .file:
            if let url = fileURLs(for: item).first {
                provider.registerObject(url as NSURL, visibility: .all)
                registeredAny = true
            }
        case .image:
            if let url = ensureImageTempFile(for: item) {
                provider.registerObject(url as NSURL, visibility: .all)
                registeredAny = true
            }
        default:
            break
        }

        // Internal representation — always present so drag-to-reorder works
        // for every kind, including text/url/color that have no file.
        // We advertise the UUID under BOTH our custom UTI and public.text.
        // SwiftUI's `.onDrop(of:)` matches against declared UTIs at accept
        // time; on some macOS versions it silently ignores a custom UTI that
        // isn't listed in the app's UTImportedTypeDeclarations. public.text
        // is guaranteed to be accepted, so the drop handler always fires
        // and can inspect the payload to decide if it's ours.
        let uuidString = item.id.uuidString
        let payload = "\(internalPayloadPrefix)\(uuidString)"
        let payloadData = payload.data(using: .utf8) ?? Data()
        provider.registerDataRepresentation(
            forTypeIdentifier: internalUUIDType,
            visibility: .all
        ) { completion in
            completion(payloadData, nil)
            return nil
        }
        provider.registerDataRepresentation(
            forTypeIdentifier: "public.utf8-plain-text",
            visibility: .ownProcess
        ) { completion in
            completion(payloadData, nil)
            return nil
        }
        registeredAny = true

        return registeredAny ? provider : nil
    }

    /// Every dragged card includes a UUID payload prefixed with this
    /// literal, so the drop handler can distinguish a Kaste-internal
    /// reorder from an unrelated text drop.
    static let internalPayloadPrefix = "kaste://item/"

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
