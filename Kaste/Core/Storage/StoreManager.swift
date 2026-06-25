import Foundation
import SwiftData
import SQLite3

/// Owns the SQLite-backed store URL and takes consistent online snapshots
/// every 30 minutes via SQLite's `sqlite3_backup` API (safe while the live
/// database is being written to). If the live store fails to open on a
/// subsequent launch (e.g., previous process SIGABRT'd mid-write and the
/// WAL got truncated), restores from the newest viable snapshot.
enum StoreManager {
    private static let storeFilename = "default.store"
    private static let liveExtensions = ["", "-wal", "-shm"]
    private static let backupsToKeep = 8
    static let backupInterval: TimeInterval = 30 * 60 // 30 min

    static var storeDirectory: URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )) ?? URL.homeDirectory.appending(path: "Library/Application Support")
        let bundleID = Bundle.main.bundleIdentifier ?? "app.kaste.Kaste"
        let dir = base.appending(path: bundleID, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var storeURL: URL { storeDirectory.appending(path: storeFilename) }

    static var backupRoot: URL {
        let dir = storeDirectory.appending(path: "backups", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Container lifecycle

    /// Open the store. On failure, swap in the newest viable backup and retry.
    /// On success, take an immediate snapshot capturing the just-recovered
    /// state.
    static func makeContainer() throws -> ModelContainer {
        // Pre-1.1.17 builds used SwiftData's implicit default location at
        // ~/Library/Application Support/default.store (no bundleID subfolder).
        // 1.1.17 introduced an explicit URL inside the bundleID subfolder.
        // Migrate any orphaned legacy store into the managed location so
        // upgraders don't appear to lose all their history.
        migrateLegacyStoreIfNeeded()

        do {
            let container = try ModelContainer(
                for: ClipItem.self,
                configurations: ModelConfiguration(url: storeURL)
            )
            snapshotNow()
            return container
        } catch {
            NSLog("Kaste: store failed to open — \(error). Trying backup restore.")
            try restoreLatestBackup()
            let container = try ModelContainer(
                for: ClipItem.self,
                configurations: ModelConfiguration(url: storeURL)
            )
            snapshotNow()
            return container
        }
    }

    // MARK: - Legacy migration

    private static func migrateLegacyStoreIfNeeded() {
        let appSupport = storeDirectory.deletingLastPathComponent()
        let legacyMain = appSupport.appending(path: storeFilename)
        guard FileManager.default.fileExists(atPath: legacyMain.path) else { return }

        // Only migrate if the managed location is empty/missing — never trample
        // a real store that already lives there.
        let managedMain = storeURL
        let managedExists = FileManager.default.fileExists(atPath: managedMain.path)
        let managedSize = (try? FileManager.default.attributesOfItem(atPath: managedMain.path)[.size] as? Int) ?? 0
        let legacySize = (try? FileManager.default.attributesOfItem(atPath: legacyMain.path)[.size] as? Int) ?? 0

        // If the managed store has meaningful contents, leave both alone.
        if managedExists && managedSize > legacySize / 4 { return }

        NSLog("Kaste: migrating legacy store \(legacyMain.path) -> \(managedMain.path)")

        // Move the empty/tiny managed store out of the way so the migrated one
        // takes its place cleanly.
        let stamp = timestamp()
        for ext in liveExtensions {
            let stale = storeDirectory.appending(path: storeFilename + ext)
            if FileManager.default.fileExists(atPath: stale.path) {
                let parked = storeDirectory.appending(path: "\(storeFilename)\(ext).pre-migrate.\(stamp)")
                try? FileManager.default.moveItem(at: stale, to: parked)
            }
        }
        for ext in liveExtensions {
            let src = appSupport.appending(path: storeFilename + ext)
            guard FileManager.default.fileExists(atPath: src.path) else { continue }
            let dst = storeDirectory.appending(path: storeFilename + ext)
            do {
                try FileManager.default.moveItem(at: src, to: dst)
            } catch {
                NSLog("Kaste: legacy migrate failed for \(ext): \(error)")
            }
        }
    }

    // MARK: - Snapshot

    /// Takes a consistent online snapshot of the live database using SQLite's
    /// backup API. Safe to call at any time, even while SwiftData is mid-write.
    /// Each snapshot is a single `default.store` file with no WAL/SHM — the
    /// backup API folds everything in.
    static func snapshotNow() {
        let srcPath = storeURL.path
        guard FileManager.default.fileExists(atPath: srcPath) else { return }

        let folder = backupRoot.appending(path: timestamp(), directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            NSLog("Kaste: snapshot mkdir failed — \(error)")
            return
        }

        let dstPath = folder.appending(path: storeFilename).path
        let ok = onlineCopy(srcPath: srcPath, dstPath: dstPath)
        if ok {
            pruneOldBackups()
        } else {
            try? FileManager.default.removeItem(at: folder)
            NSLog("Kaste: sqlite_backup failed; snapshot discarded")
        }
    }

    // MARK: - Restore

    private static func restoreLatestBackup() throws {
        let snapshots = listBackups()
        guard !snapshots.isEmpty else {
            throw NSError(domain: "Kaste.StoreManager", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No backups available to restore from."
            ])
        }

        // Move corrupted live files aside before restoring.
        let corruptedDir = storeDirectory.appending(path: ".corrupted", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: corruptedDir, withIntermediateDirectories: true)
        let stamp = timestamp()
        for ext in liveExtensions {
            let src = storeDirectory.appending(path: storeFilename + ext)
            guard FileManager.default.fileExists(atPath: src.path) else { continue }
            let dst = corruptedDir.appending(path: "\(storeFilename)\(ext).\(stamp)")
            try? FileManager.default.moveItem(at: src, to: dst)
        }

        // Walk newest → oldest until one restore succeeds. Snapshots store a
        // single .store file (the backup API consolidated everything), so
        // restored live dir has no stale WAL/SHM either.
        for snapshot in snapshots {
            let backup = snapshot.appending(path: storeFilename)
            guard FileManager.default.fileExists(atPath: backup.path) else {
                NSLog("Kaste: backup \(snapshot.lastPathComponent) missing store file")
                continue
            }
            let dst = storeURL
            try? FileManager.default.removeItem(at: dst)
            do {
                try FileManager.default.copyItem(at: backup, to: dst)
                NSLog("Kaste: restored store from backup \(snapshot.lastPathComponent)")
                return
            } catch {
                NSLog("Kaste: backup \(snapshot.lastPathComponent) copy failed — \(error)")
            }
        }
        throw NSError(domain: "Kaste.StoreManager", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "All backups failed to restore."
        ])
    }

    // MARK: - SQLite online backup

    /// Uses SQLite's sqlite3_backup_init/step/finish to produce a fully
    /// consistent copy of the source database. Reads only — does not lock
    /// the source for writers thanks to WAL mode.
    private static func onlineCopy(srcPath: String, dstPath: String) -> Bool {
        var src: OpaquePointer?
        var dst: OpaquePointer?
        defer {
            if let src { sqlite3_close(src) }
            if let dst { sqlite3_close(dst) }
        }

        // Open read-only for source to avoid contending with writers.
        let openFlags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(srcPath, &src, openFlags, nil) == SQLITE_OK else {
            NSLog("Kaste: snapshot open(src) failed: \(String(cString: sqlite3_errmsg(src)))")
            return false
        }
        guard sqlite3_open(dstPath, &dst) == SQLITE_OK else {
            NSLog("Kaste: snapshot open(dst) failed: \(String(cString: sqlite3_errmsg(dst)))")
            return false
        }
        guard let backup = sqlite3_backup_init(dst, "main", src, "main") else {
            NSLog("Kaste: backup_init failed: \(String(cString: sqlite3_errmsg(dst)))")
            return false
        }

        // Copy all pages in one shot; -1 means "remaining pages".
        let stepRC = sqlite3_backup_step(backup, -1)
        sqlite3_backup_finish(backup)
        if stepRC != SQLITE_DONE {
            NSLog("Kaste: backup_step rc=\(stepRC)")
            return false
        }
        return true
    }

    // MARK: - Helpers

    private static func listBackups() -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: backupRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { a, b in
                let ta = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let tb = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return ta > tb // newest first
            }
    }

    private static func pruneOldBackups() {
        let snapshots = listBackups()
        guard snapshots.count > backupsToKeep else { return }
        for stale in snapshots.dropFirst(backupsToKeep) {
            try? FileManager.default.removeItem(at: stale)
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f.string(from: Date())
    }
}
