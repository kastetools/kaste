import Foundation
import AppKit

enum UpdateChecker {
    static let repoOwner = "kastetools"
    static let repoName = "kaste"

    struct ReleaseInfo: Equatable {
        let tagName: String      // e.g. "v1.2.0"
        let version: String      // "1.2.0"
        let htmlURL: URL
        let dmgURL: URL?
    }

    enum UpdateError: LocalizedError {
        case badStatus(Int)
        case rateLimited(resetAt: Date?)
        case malformedResponse
        case noDMGAsset
        case mountFailed
        case copyFailed(String)

        var errorDescription: String? {
            switch self {
            case .badStatus(let c):     return "GitHub responded with HTTP \(c)"
            case .rateLimited(let at):
                if let at {
                    let mins = max(1, Int(ceil(at.timeIntervalSinceNow / 60)))
                    return "GitHub API rate limit reached. Try again in ~\(mins) min."
                }
                return "GitHub API rate limit reached. Try again shortly."
            case .malformedResponse:    return "Unexpected response from GitHub"
            case .noDMGAsset:           return "The latest release has no DMG asset"
            case .mountFailed:          return "Could not mount the downloaded DMG"
            case .copyFailed(let m):    return "Install script failed: \(m)"
            }
        }
    }

    // Small on-disk cache: last ETag + last decoded release JSON blob. GitHub
    // guarantees that conditional requests (`If-None-Match: <etag>`) which
    // return 304 Not Modified do NOT count against the 60/hour anonymous
    // rate limit, so this lets us check-for-updates freely once we've seen
    // one full response.
    private static let etagKey = "updateChecker.etag"
    private static let cachedReleaseKey = "updateChecker.cachedRelease"

    private static func loadCachedRelease() -> ReleaseInfo? {
        guard let data = UserDefaults.standard.data(forKey: cachedReleaseKey),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return parseRelease(from: json)
    }

    private static func saveCachedRelease(rawJSON: Data, etag: String?) {
        UserDefaults.standard.set(rawJSON, forKey: cachedReleaseKey)
        if let etag { UserDefaults.standard.set(etag, forKey: etagKey) }
    }

    private static func parseRelease(from json: [String: Any]) -> ReleaseInfo? {
        guard let tagName = json["tag_name"] as? String,
              let htmlURLString = json["html_url"] as? String,
              let htmlURL = URL(string: htmlURLString) else {
            return nil
        }
        let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        let assets = json["assets"] as? [[String: Any]] ?? []
        let dmgURL = assets.compactMap { asset -> URL? in
            guard let name = asset["name"] as? String, name.hasSuffix(".dmg"),
                  let urlStr = asset["browser_download_url"] as? String else { return nil }
            return URL(string: urlStr)
        }.first
        return ReleaseInfo(tagName: tagName, version: version,
                           htmlURL: htmlURL, dmgURL: dmgURL)
    }

    static func currentVersion() -> String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }

    /// Returns true iff `remote` is strictly newer than `local` using
    /// dot-separated integer comparison (e.g., 1.1.10 > 1.1.9).
    static func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        let len = max(r.count, l.count)
        for i in 0..<len {
            let a = i < r.count ? r[i] : 0
            let b = i < l.count ? l[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    static func fetchLatest() async throws -> ReleaseInfo {
        let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.timeoutInterval = 15
        // Conditional request: 304 Not Modified doesn't count against
        // GitHub's 60/hour anonymous rate limit.
        if let etag = UserDefaults.standard.string(forKey: etagKey) {
            req.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw UpdateError.malformedResponse }

        if http.statusCode == 304, let cached = loadCachedRelease() {
            return cached
        }

        if http.statusCode == 403 || http.statusCode == 429 {
            // Try to salvage a helpful message via cached response, else surface a clear rate-limit error.
            let resetAt = (http.value(forHTTPHeaderField: "x-ratelimit-reset")).flatMap(TimeInterval.init)
                .map { Date(timeIntervalSince1970: $0) }
            if let cached = loadCachedRelease() {
                NSLog("Kaste: update check rate-limited (HTTP \(http.statusCode)); returning cached release")
                return cached
            }
            throw UpdateError.rateLimited(resetAt: resetAt)
        }

        guard http.statusCode == 200 else { throw UpdateError.badStatus(http.statusCode) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let release = parseRelease(from: json) else {
            throw UpdateError.malformedResponse
        }
        saveCachedRelease(rawJSON: data,
                          etag: http.value(forHTTPHeaderField: "Etag")
                                ?? http.value(forHTTPHeaderField: "ETag"))
        return release
    }

    /// Downloads the DMG asset, then hands off to a detached shell script that
    /// waits for Kaste to quit, copies the new .app into /Applications, ejects
    /// the DMG and relaunches Kaste. Kaste terminates itself on success.
    static func downloadAndInstall(_ release: ReleaseInfo) async throws {
        guard let dmgURL = release.dmgURL else { throw UpdateError.noDMGAsset }

        var req = URLRequest(url: dmgURL)
        req.timeoutInterval = 120 // DMG can be big; 2 minutes is generous
        let (tempLocal, _) = try await URLSession.shared.download(for: req)
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kaste-\(release.version).dmg")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tempLocal, to: dest)

        await MainActor.run {
            do {
                try Self.runInstaller(dmgPath: dest.path)
            } catch {
                NSLog("Kaste: runInstaller failed: \(error)")
            }
        }
    }

    @MainActor
    private static func runInstaller(dmgPath: String) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("kaste-installer-\(pid).sh")

        // Install over the currently-running bundle location — /Applications
        // isn't always writable (managed Macs, non-admin users). Users who
        // dropped Kaste in ~/Applications get updated in place.
        let currentBundle = Bundle.main.bundleURL.path

        let script = #"""
        #!/bin/bash
        PID="__PID__"
        DMG="__DMG__"
        DEST="__DEST__"
        LOG="/tmp/kaste-installer.log"

        exec >>"$LOG" 2>&1
        echo "---- $(date) installer start, pid=$PID, dmg=$DMG ----"

        # Wait for Kaste to quit (max 30s)
        for i in $(seq 1 60); do
          kill -0 "$PID" 2>/dev/null || break
          sleep 0.5
        done
        sleep 1

        MOUNT_OUT=$(/usr/bin/hdiutil attach "$DMG" -nobrowse 2>&1)
        VOLUME=$(echo "$MOUNT_OUT" | /usr/bin/awk -F'\t' '/\/Volumes\// {print $NF}' | /usr/bin/tail -1)
        if [ -z "$VOLUME" ] || [ ! -d "$VOLUME/Kaste.app" ]; then
          echo "Mount failed or no Kaste.app on volume"
          echo "$MOUNT_OUT"
          exit 1
        fi

        if ! /usr/bin/ditto "$VOLUME/Kaste.app" "$DEST"; then
          echo "ditto failed — $DEST likely not writable"
          /usr/bin/hdiutil detach "$VOLUME" -quiet
          MARKER="$HOME/Desktop/Kaste-update-FAILED.txt"
          {
            echo "Kaste automatic update failed."
            echo ""
            echo "Reason: could not write to $DEST"
            echo "Downloaded DMG kept at: $DMG"
            echo ""
            echo "Fix: open the DMG and drag Kaste.app to a writable Applications folder."
          } > "$MARKER"
          /usr/bin/open -R "$DMG"
          exit 1
        fi
        /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

        /usr/bin/hdiutil detach "$VOLUME" -quiet || true
        /bin/rm -f "$DMG"

        /usr/bin/open "$DEST"
        /bin/rm -- "$0"
        """#
        .replacingOccurrences(of: "__PID__", with: "\(pid)")
        .replacingOccurrences(of: "__DMG__", with: dmgPath)
        .replacingOccurrences(of: "__DEST__", with: currentBundle)

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: scriptURL.path)

        // Detached launch so the script outlives Kaste.
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", "nohup \"\(scriptURL.path)\" </dev/null >/dev/null 2>&1 &"]
        try task.run()
        task.waitUntilExit()

        // Hand control to the installer.
        NSApp.terminate(nil)
    }
}
