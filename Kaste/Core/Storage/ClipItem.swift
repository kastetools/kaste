import Foundation
import SwiftData

enum ClipKind: String, Codable, CaseIterable {
    case text, rtf, image, file, url, color

    var symbol: String {
        switch self {
        case .text:  return "text.alignleft"
        case .rtf:   return "doc.richtext"
        case .image: return "photo"
        case .file:  return "doc"
        case .url:   return "link"
        case .color: return "paintpalette"
        }
    }

    var label: String {
        switch self {
        case .text:  return "Text"
        case .rtf:   return "Rich Text"
        case .image: return "Image"
        case .file:  return "File"
        case .url:   return "Link"
        case .color: return "Color"
        }
    }
}

@Model
final class ClipItem {
    #Index<ClipItem>([\.lastUsedAt], [\.isPinned], [\.kindRaw], [\.contentHash], [\.sortRank])

    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var lastUsedAt: Date
    var useCount: Int
    var isPinned: Bool
    var kindRaw: String
    var contentHash: String
    /// Display order (DESC — larger = further left / on top). Defaults to
    /// the insert timestamp so new items surface first, but the user can
    /// drag cards to any position and we recompute this rank to sit
    /// between their new neighbours. `lastUsedAt` keeps its retention
    /// semantics; sortRank is purely visual order.
    var sortRank: Double

    var plainText: String?
    var searchKey: String?
    var rtfData: Data?
    @Attribute(.externalStorage) var imageData: Data?
    var filePaths: [String]?
    var colorHex: String?

    @Attribute(.externalStorage) var pasteboardArchive: Data?

    var sourceBundleID: String?
    var sourceAppName: String?

    init(
        kind: ClipKind,
        hash: String,
        plainText: String? = nil,
        rtfData: Data? = nil,
        imageData: Data? = nil,
        filePaths: [String]? = nil,
        colorHex: String? = nil,
        pasteboardArchive: Data? = nil,
        sourceBundleID: String? = nil,
        sourceAppName: String? = nil
    ) {
        self.id = UUID()
        let now = Date()
        self.createdAt = now
        self.lastUsedAt = now
        self.sortRank = now.timeIntervalSince1970
        self.useCount = 0
        self.isPinned = false
        self.kindRaw = kind.rawValue
        self.contentHash = hash
        self.plainText = plainText
        self.searchKey = plainText?.lowercased()
        self.rtfData = rtfData
        self.imageData = imageData
        self.filePaths = filePaths
        self.colorHex = colorHex
        self.pasteboardArchive = pasteboardArchive
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
    }

    var kind: ClipKind { ClipKind(rawValue: kindRaw) ?? .text }
}
