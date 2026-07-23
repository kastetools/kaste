import SwiftUI
import AppKit

/// Bounded cache of decoded NSImages keyed by ClipItem.id. Prevents
/// re-decoding large TIFF/PNG blobs every time LazyHStack recycles a card,
/// which was causing frame drops when scrolling through image-heavy history.
enum ClipImageCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 64
        c.totalCostLimit = 128 * 1024 * 1024 // 128 MB
        return c
    }()

    static func image(for id: UUID, data: Data) -> NSImage? {
        let key = id.uuidString as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let img = NSImage(data: data) else { return nil }
        cache.setObject(img, forKey: key, cost: data.count)
        return img
    }

    /// Load an image directly from a file URL (used for file-kind cards
    /// whose path points at a PNG/JPG/etc.). Falls back to nil if the file
    /// is gone or unreadable, so the caller can render a file-icon.
    static func image(forID id: UUID, fileURL: URL) -> NSImage? {
        let key = id.uuidString as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let img = NSImage(contentsOf: fileURL) else { return nil }
        let cost = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        cache.setObject(img, forKey: key, cost: cost)
        return img
    }

    static func drop(_ id: UUID) {
        cache.removeObject(forKey: id.uuidString as NSString)
    }
}

private let imageFileExtensions: Set<String> = [
    "png", "jpg", "jpeg", "gif", "heic", "heif",
    "webp", "bmp", "tiff", "tif"
]

private func isImagePath(_ path: String) -> Bool {
    imageFileExtensions.contains((path as NSString).pathExtension.lowercased())
}

struct ClipCardView: View, Equatable {
    let item: ClipItem
    let index: Int
    let isSelected: Bool

    /// SwiftUI uses this via `.equatable()` to skip body evaluation when
    /// nothing user-visible changed. We deliberately compare only stable/
    /// identifying values — never touch properties that could fault on a
    /// deleted @Model (the modelContext guard in body handles the render
    /// side; == mirrors it so we don't return "unchanged" across a stale
    /// vs. fresh reference and skip a needed re-draw).
    static func == (a: ClipCardView, b: ClipCardView) -> Bool {
        let aValid = a.item.modelContext != nil
        let bValid = b.item.modelContext != nil
        if aValid != bValid { return false }
        if !aValid { return a.item.id == b.item.id }
        return a.item.id == b.item.id
            && a.item.isPinned == b.item.isPinned
            && a.item.lastUsedAt == b.item.lastUsedAt
            && a.index == b.index
            && a.isSelected == b.isSelected
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var bannerNSColor: NSColor {
        AppColorExtractor.nsColor(forBundleID: item.sourceBundleID)
            ?? NSColor(srgbRed: 0.55, green: 0.55, blue: 0.6, alpha: 1)
    }
    private var bannerColor: Color { Color(nsColor: bannerNSColor) }
    private var bannerForeground: Color { AppColorExtractor.onColor(for: bannerNSColor) }
    private var appIcon: NSImage? { AppColorExtractor.appIcon(forBundleID: item.sourceBundleID) }

    var body: some View {
        Group {
            // Guard against SwiftData asserting when we read a property of a
            // ClipItem that was just deleted (dedup / retention / capacity
            // cleanup) but @Query hasn't republished the array yet.
            if item.modelContext == nil {
                Color.clear
            } else {
                VStack(spacing: 0) {
                    banner
                    bodyArea
                    footer
                }
            }
        }
        .frame(width: 224, height: 224)
        .background(Color(nsColor: NSColor.windowBackgroundColor).opacity(isSelected ? 1.0 : 0.92))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : .white.opacity(0.06),
                              lineWidth: isSelected ? 2 : 1)
        )
        .scaleEffect(isSelected ? 1.0 : 0.97)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    // MARK: - Banner

    private var banner: some View {
        ZStack(alignment: .topLeading) {
            bannerColor

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.kind.label)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(Self.relativeFormatter.localizedString(for: item.lastUsedAt, relativeTo: Date()))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.leading, 12)

                Spacer(minLength: 0)

                if let icon = appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(height: 60)
                }
            }

            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.22), in: Circle())
                    .padding(6)
            }
        }
        .frame(height: 60)
        .clipped()
    }

    // MARK: - Body

    private var bodyArea: some View {
        preview
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
    }

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .image:
            if let data = item.imageData, let img = ClipImageCache.image(for: item.id, data: data) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: "photo").font(.system(size: 36))
                    .foregroundStyle(.secondary)
            }
        case .color:
            if let hex = item.colorHex, let color = Color(hex: hex) {
                RoundedRectangle(cornerRadius: 8).fill(color)
                Text(hex.uppercased())
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else { Color.gray }
        case .file:
            let firstPath = item.filePaths?.first
            let extraCount = (item.filePaths?.count ?? 0) - 1
            if let path = firstPath, isImagePath(path),
               let img = ClipImageCache.image(forID: item.id,
                                              fileURL: URL(fileURLWithPath: path)) {
                VStack(spacing: 4) {
                    Image(nsImage: img)
                        .resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if extraCount > 0 {
                        Text("+\(extraCount) more")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "doc.fill").font(.system(size: 28))
                        .foregroundStyle(bannerColor)
                    Text((firstPath as NSString?)?.lastPathComponent ?? "")
                        .font(.system(size: 11)).lineLimit(2)
                        .multilineTextAlignment(.center)
                    if extraCount > 0 {
                        Text("+\(extraCount) more")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .url:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 16))
                    .foregroundStyle(bannerColor)
                Text(item.plainText ?? "")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(4)
                    .foregroundStyle(.primary)
            }
        case .rtf, .text:
            Text(item.plainText ?? "")
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            if let secondary = secondaryFooter {
                Text(secondary)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .padding(.top, 4)
    }

    private var secondaryFooter: String? {
        switch item.kind {
        case .text, .rtf, .url, .color:
            if let t = item.plainText {
                return "\(t.count) chars"
            }
            return nil
        case .image:
            if let data = item.imageData, let img = ClipImageCache.image(for: item.id, data: data) {
                return "\(Int(img.size.width))×\(Int(img.size.height))"
            }
            return nil
        case .file:
            return "\(item.filePaths?.count ?? 0) file\(item.filePaths?.count == 1 ? "" : "s")"
        }
    }
}

extension Color {
    init?(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}
