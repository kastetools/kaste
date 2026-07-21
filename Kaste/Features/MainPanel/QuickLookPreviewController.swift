import AppKit
import Quartz

/// Finder-style Quick Look preview via `QLPreviewPanel.shared()` —
/// the same panel that opens when you hit Space on a file in Finder.
/// Reuses the shared instance so preview is instant (no subprocess
/// launch like the old `qlmanage -p` path).
///
/// For clip kinds that aren't natively backed by a file (text / rtf /
/// url / color) we lazily materialize a temp file the first time the
/// item is previewed, then reuse it.
@MainActor
final class QuickLookPreviewController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookPreviewController()

    private var currentItem: QuickLookItem?

    func preview(_ item: ClipItem) {
        guard let url = urlForPreview(item) else {
            KLog.log("QuickLook: no previewable URL for kind=\(item.kind)")
            return
        }
        let title = displayTitle(for: item)
        currentItem = QuickLookItem(url: url, title: title)

        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        if panel.isVisible {
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        currentItem == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        currentItem
    }

    // MARK: - URL materialization

    private func urlForPreview(_ item: ClipItem) -> URL? {
        switch item.kind {
        case .file:
            return (item.filePaths ?? []).first.map { URL(fileURLWithPath: $0) }
        case .image:
            return ItemActions.ensureImageTempFile(for: item)
        case .text, .url:
            return writeText(item.plainText ?? "", id: item.id, ext: "txt")
        case .rtf:
            if let data = item.rtfData {
                return writeData(data, id: item.id, ext: "rtf")
            }
            return writeText(item.plainText ?? "", id: item.id, ext: "txt")
        case .color:
            return writeColorSwatch(item.colorHex ?? "#000000", id: item.id)
        }
    }

    private func displayTitle(for item: ClipItem) -> String {
        switch item.kind {
        case .file:
            let path = (item.filePaths ?? []).first ?? ""
            return (path as NSString).lastPathComponent
        case .image, .color:
            return item.kind.label
        case .text, .rtf, .url:
            let s = item.plainText ?? ""
            let firstLine = s.split(whereSeparator: \.isNewline).first.map(String.init) ?? item.kind.label
            return firstLine.count > 64 ? String(firstLine.prefix(64)) + "…" : firstLine
        }
    }

    private func writeText(_ text: String, id: UUID, ext: String) -> URL? {
        let url = ItemActions.tempDir.appendingPathComponent("\(id.uuidString).\(ext)")
        if !FileManager.default.fileExists(atPath: url.path) {
            do { try text.write(to: url, atomically: true, encoding: .utf8) }
            catch { KLog.log("QuickLook: text tempfile write failed: \(error)"); return nil }
        }
        return url
    }

    private func writeData(_ data: Data, id: UUID, ext: String) -> URL? {
        let url = ItemActions.tempDir.appendingPathComponent("\(id.uuidString).\(ext)")
        if !FileManager.default.fileExists(atPath: url.path) {
            do { try data.write(to: url) }
            catch { KLog.log("QuickLook: data tempfile write failed: \(error)"); return nil }
        }
        return url
    }

    private func writeColorSwatch(_ hex: String, id: UUID) -> URL? {
        let url = ItemActions.tempDir.appendingPathComponent("\(id.uuidString).html")
        if !FileManager.default.fileExists(atPath: url.path) {
            let html = """
            <!DOCTYPE html>
            <html><head><meta charset="utf-8"><title>\(hex)</title></head>
            <body style="margin:0;display:flex;flex-direction:column;align-items:center;justify-content:center;height:100vh;background:#f6f6f8;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#1f1f21">
              <div style="width:60vmin;height:60vmin;background:\(hex);border-radius:32px;box-shadow:0 24px 64px rgba(0,0,0,.22)"></div>
              <div style="margin-top:32px;font-size:34px;font-family:'SF Mono',Menlo,monospace;letter-spacing:.5px">\(hex.uppercased())</div>
            </body></html>
            """
            do { try html.write(to: url, atomically: true, encoding: .utf8) }
            catch { KLog.log("QuickLook: color swatch write failed: \(error)"); return nil }
        }
        return url
    }
}

private final class QuickLookItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?
    let previewItemTitle: String?
    init(url: URL, title: String?) {
        self.previewItemURL = url
        self.previewItemTitle = title
    }
}
