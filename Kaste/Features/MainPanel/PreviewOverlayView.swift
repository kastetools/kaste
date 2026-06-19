import SwiftUI
import AppKit

struct PreviewOverlayView: View {
    let item: ClipItem
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            content
            Divider().opacity(0.4)
            footer
        }
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 28, y: 10)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: item.kind.symbol).foregroundStyle(.tint)
            Text(item.kind.label).font(.system(size: 12, weight: .semibold))
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10)).foregroundStyle(.orange)
            }
            Spacer()
            if let app = item.sourceAppName {
                Text(app).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text, .rtf, .url:
            ScrollView {
                Text(item.plainText ?? "")
                    .font(.system(size: 13, design: item.kind == .url ? .monospaced : .default))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        case .image:
            if let data = item.imageData, let nsimg = NSImage(data: data) {
                Image(nsImage: nsimg)
                    .resizable()
                    .scaledToFit()
                    .padding(14)
            } else {
                placeholder("No image data")
            }
        case .file:
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(item.filePaths ?? [], id: \.self) { p in
                        HStack(spacing: 6) {
                            Image(systemName: "doc").foregroundStyle(.secondary)
                            Text(p).font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
        case .color:
            HStack(spacing: 16) {
                if let hex = item.colorHex, let color = colorFromHex(hex) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(color)
                        .frame(width: 120, height: 120)
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.white.opacity(0.15), lineWidth: 1))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.colorHex ?? "")
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                    Text("Press \(Image(systemName: "return")) to paste")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            label("Created", item.createdAt.formatted(date: .abbreviated, time: .shortened))
            label("Last used", item.lastUsedAt.formatted(date: .abbreviated, time: .shortened))
            label("Uses", "\(item.useCount)")
            Spacer()
            Text("Space / Esc to close").font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func label(_ k: String, _ v: String) -> some View {
        HStack(spacing: 4) {
            Text(k).font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            Text(v).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private func placeholder(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func colorFromHex(_ hex: String) -> Color? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let val = UInt32(s, radix: 16) else { return nil }
        return Color(
            red:   Double((val >> 16) & 0xff) / 255,
            green: Double((val >> 8)  & 0xff) / 255,
            blue:  Double(val         & 0xff) / 255
        )
    }
}
