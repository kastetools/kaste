import Foundation
import AppKit

/// Central logger. Every call is mirrored to two places:
///   1. `NSLog` — visible in Console.app immediately, tagged "Kaste:".
///   2. `~/Library/Logs/Kaste/kaste.log` — an append-only file the user can
///      grab and send back. Auto-rotates at 5 MB (one .log.1 backup kept).
///
/// Uses a serial queue for the file writes so simultaneous calls from
/// different threads don't interleave partial lines.
enum KLog {

    /// Reveal the log folder in Finder so the user can grab the file.
    static func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([logURL])
    }

    static var logURL: URL { fileURL }
    static var logDirectory: URL { fileURL.deletingLastPathComponent() }

    static func log(_ message: String,
                    file: String = #fileID,
                    line: Int = #line) {
        let shortFile = (file as NSString).lastPathComponent
        NSLog("Kaste: \(message)")
        appendToFile("[\(Self.timestamp())] \(shortFile):\(line) — \(message)\n")
    }

    // MARK: - Internals

    private static let fileURL: URL = {
        let base = (try? FileManager.default.url(
            for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        )) ?? URL.homeDirectory.appending(path: "Library")
        let dir = base.appending(path: "Logs/Kaste", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "kaste.log")
    }()

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let writeQueue = DispatchQueue(label: "app.kaste.log", qos: .utility)
    private static let maxSize: Int = 5 * 1024 * 1024 // 5 MB

    private static func timestamp() -> String {
        timestampFormatter.string(from: Date())
    }

    private static func appendToFile(_ line: String) {
        writeQueue.async {
            rotateIfNeeded()
            guard let data = line.data(using: .utf8) else { return }
            let fm = FileManager.default
            if !fm.fileExists(atPath: fileURL.path) {
                fm.createFile(atPath: fileURL.path, contents: nil)
            }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } catch {
                    // Best effort — a dropped log line is preferable to a crash.
                }
            }
        }
    }

    private static func rotateIfNeeded() {
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        guard size > maxSize else { return }
        let backup = fileURL.deletingLastPathComponent().appending(path: "kaste.log.1")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: fileURL, to: backup)
    }
}
