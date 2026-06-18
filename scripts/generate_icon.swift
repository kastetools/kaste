#!/usr/bin/env swift
import AppKit

// Kaste app icon — generates the AppIcon.appiconset PNGs.
//
// Concept: a soft-coral → magenta gradient rounded square (macOS Big Sur style),
// with a white clipboard glyph and a bold "K" mark embossed on the clip.

let outDir = CommandLine.arguments.dropFirst().first
    ?? "Kaste/Resources/Assets.xcassets/AppIcon.appiconset"

let fm = FileManager.default
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(size: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 32
    )!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let ctx = NSGraphicsContext.current!.cgContext
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * 0.225 // macOS squircle-ish

    // Background gradient.
    let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(srgbRed: 1.00, green: 0.42, blue: 0.42, alpha: 1.0), // coral
        CGColor(srgbRed: 0.93, green: 0.18, blue: 0.55, alpha: 1.0)  // magenta
    ] as CFArray
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: 0, y: size),
                           end: CGPoint(x: size, y: 0),
                           options: [])

    // Subtle inner highlight (top-left glow).
    let glow = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.28),
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: size * 0.25, y: size * 0.85),
        startRadius: 0,
        endCenter: CGPoint(x: size * 0.25, y: size * 0.85),
        endRadius: size * 0.7,
        options: []
    )
    ctx.restoreGState()

    // Clipboard glyph.
    let clipW = size * 0.50
    let clipH = size * 0.62
    let clipX = (size - clipW) / 2
    let clipY = (size - clipH) / 2 - size * 0.02
    let clipRadius = size * 0.06

    // Card body.
    let cardRect = CGRect(x: clipX, y: clipY, width: clipW, height: clipH)
    let cardPath = CGPath(roundedRect: cardRect, cornerWidth: clipRadius, cornerHeight: clipRadius, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012),
                  blur: size * 0.04,
                  color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.25))
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.96))
    ctx.addPath(cardPath)
    ctx.fillPath()
    ctx.restoreGState()

    // Clip tab on top.
    let tabW = clipW * 0.42
    let tabH = size * 0.085
    let tabRect = CGRect(
        x: clipX + (clipW - tabW) / 2,
        y: clipY + clipH - tabH * 0.55,
        width: tabW, height: tabH
    )
    let tabPath = CGPath(roundedRect: tabRect, cornerWidth: tabH * 0.32, cornerHeight: tabH * 0.32, transform: nil)
    ctx.setFillColor(CGColor(srgbRed: 0.18, green: 0.10, blue: 0.18, alpha: 1.0))
    ctx.addPath(tabPath)
    ctx.fillPath()

    // "K" letter, bold.
    let letterFontSize = clipH * 0.55
    let font = NSFont.systemFont(ofSize: letterFontSize, weight: .heavy)
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(srgbRed: 0.93, green: 0.18, blue: 0.55, alpha: 1.0),
        .paragraphStyle: para,
        .kern: -letterFontSize * 0.02
    ]
    let letter = NSAttributedString(string: "K", attributes: attrs)
    let textSize = letter.size()
    let textRect = CGRect(
        x: clipX + (clipW - textSize.width) / 2,
        y: clipY + (clipH - textSize.height) / 2 - size * 0.02,
        width: textSize.width,
        height: textSize.height
    )
    letter.draw(in: textRect)

    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to path: String) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 1)
    }
    try data.write(to: URL(fileURLWithPath: path))
}

struct IconSpec {
    let size: CGFloat
    let scale: Int
    let filename: String
}

let specs: [IconSpec] = [
    .init(size: 16,   scale: 1, filename: "icon_16x16.png"),
    .init(size: 16,   scale: 2, filename: "icon_16x16@2x.png"),
    .init(size: 32,   scale: 1, filename: "icon_32x32.png"),
    .init(size: 32,   scale: 2, filename: "icon_32x32@2x.png"),
    .init(size: 128,  scale: 1, filename: "icon_128x128.png"),
    .init(size: 128,  scale: 2, filename: "icon_128x128@2x.png"),
    .init(size: 256,  scale: 1, filename: "icon_256x256.png"),
    .init(size: 256,  scale: 2, filename: "icon_256x256@2x.png"),
    .init(size: 512,  scale: 1, filename: "icon_512x512.png"),
    .init(size: 512,  scale: 2, filename: "icon_512x512@2x.png"),
]

for spec in specs {
    let pixel = spec.size * CGFloat(spec.scale)
    let img = render(size: pixel)
    let path = "\(outDir)/\(spec.filename)"
    try writePNG(img, to: path)
    print("wrote \(path) @ \(Int(pixel))px")
}

// Contents.json
struct ContentsEntry: Codable {
    let size: String
    let idiom: String
    let filename: String
    let scale: String
}
struct Contents: Codable {
    let images: [ContentsEntry]
    let info: [String: String]
}

let entries = specs.map {
    ContentsEntry(
        size: "\(Int($0.size))x\(Int($0.size))",
        idiom: "mac",
        filename: $0.filename,
        scale: "\($0.scale)x"
    )
}
let contents = Contents(
    images: entries,
    info: ["version": "1", "author": "kaste"]
)
let enc = JSONEncoder()
enc.outputFormatting = [.prettyPrinted, .sortedKeys]
let json = try enc.encode(contents)
try json.write(to: URL(fileURLWithPath: "\(outDir)/Contents.json"))
print("wrote \(outDir)/Contents.json")

// Also emit a single full-res logo for docs / README.
let bigPath = (outDir as NSString).deletingLastPathComponent + "/../../logo_1024.png"
let big = render(size: 1024)
try writePNG(big, to: bigPath)
print("wrote \(bigPath)")
