import AppKit
import SwiftUI

/// Extracts a dominant brand color from an app's icon, keyed by bundle ID.
/// Pixels are HSV-binned by hue; the heaviest vivid bin wins.
@MainActor
enum AppColorExtractor {
    private static var colorCache: [String: NSColor] = [:]
    private static var iconCache: [String: NSImage] = [:]

    static func color(forBundleID bundleID: String?) -> Color? {
        guard let bundleID else { return nil }
        if let cached = colorCache[bundleID] { return Color(nsColor: cached) }
        guard let icon = appIcon(forBundleID: bundleID) else { return nil }
        let dominant = extract(from: icon)
        colorCache[bundleID] = dominant
        return Color(nsColor: dominant)
    }

    static func appIcon(forBundleID bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = iconCache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[bundleID] = icon
        return icon
    }

    /// Returns a high-contrast foreground color (white or near-black) for text drawn over `banner`.
    static func onColor(for banner: NSColor) -> Color {
        let srgb = banner.usingColorSpace(.sRGB) ?? banner
        let lum = 0.2126 * Double(srgb.redComponent)
               + 0.7152 * Double(srgb.greenComponent)
               + 0.0722 * Double(srgb.blueComponent)
        return lum > 0.62 ? Color.black.opacity(0.85) : Color.white
    }

    static func nsColor(forBundleID bundleID: String?) -> NSColor? {
        guard let bundleID else { return nil }
        if let cached = colorCache[bundleID] { return cached }
        guard let icon = appIcon(forBundleID: bundleID) else { return nil }
        let dominant = extract(from: icon)
        colorCache[bundleID] = dominant
        return dominant
    }

    private static func extract(from icon: NSImage) -> NSColor {
        let size = 32
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 32
        ) else { return .gray }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        icon.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()

        struct Bin { var r = 0.0; var g = 0.0; var b = 0.0; var w = 0.0 }
        var bins = Array(repeating: Bin(), count: 12)

        for y in 0..<size {
            for x in 0..<size {
                guard let c = rep.colorAt(x: x, y: y) else { continue }
                let r = Double(c.redComponent)
                let g = Double(c.greenComponent)
                let b = Double(c.blueComponent)
                let a = Double(c.alphaComponent)
                if a < 0.5 { continue }

                let maxC = max(r, g, b)
                let minC = min(r, g, b)
                let delta = maxC - minC
                let v = maxC
                let s = maxC == 0 ? 0 : delta / maxC
                // Skip greyscale / too dark / too light noise.
                if s < 0.25 || v < 0.2 || v > 0.97 { continue }

                var h: Double = 0
                if delta > 0 {
                    if maxC == r { h = (g - b) / delta }
                    else if maxC == g { h = 2 + (b - r) / delta }
                    else { h = 4 + (r - g) / delta }
                    h *= 60
                    if h < 0 { h += 360 }
                }
                let bin = Int(h / 30) % 12
                let weight = s * s * v
                bins[bin].r += r * weight
                bins[bin].g += g * weight
                bins[bin].b += b * weight
                bins[bin].w += weight
            }
        }

        guard let best = bins.max(by: { $0.w < $1.w }), best.w > 0 else {
            return NSColor(srgbRed: 0.55, green: 0.55, blue: 0.6, alpha: 1)
        }
        return NSColor(
            srgbRed: CGFloat(best.r / best.w),
            green: CGFloat(best.g / best.w),
            blue: CGFloat(best.b / best.w),
            alpha: 1
        )
    }
}
