import AppKit

let args = CommandLine.arguments
let outDir = args.count > 1 ? args[1] : "build/AppIcon.iconset"
let inputIcon = args.count > 2 ? args[2] : "assets/icon_mac.png"

let fm = FileManager.default
try? fm.removeItem(atPath: outDir)
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// Prefer pre-padded icon_mac.png if inputIcon is default assets/icon.png
var resolvedInput = inputIcon
if inputIcon == "assets/icon.png" && fm.fileExists(atPath: "assets/icon_mac.png") {
    resolvedInput = "assets/icon_mac.png"
}

guard let rawImg = NSImage(contentsOfFile: resolvedInput),
      let cgImage = rawImg.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("Error: Could not load source icon at \(resolvedInput)\n", stderr)
    exit(1)
}

// Check if source image touches canvas edges (cardinal points on 1024x1024 canvas)
func isFullBleed(img: NSImage) -> Bool {
    guard let rep = img.representations.first as? NSBitmapImageRep else { return false }
    let w = rep.pixelsWide
    let h = rep.pixelsHigh
    let top = rep.colorAt(x: w / 2, y: 15)?.alphaComponent ?? 0
    let bottom = rep.colorAt(x: w / 2, y: h - 16)?.alphaComponent ?? 0
    let left = rep.colorAt(x: 15, y: h / 2)?.alphaComponent ?? 0
    let right = rep.colorAt(x: w - 16, y: h / 2)?.alphaComponent ?? 0
    return top > 0.05 || bottom > 0.05 || left > 0.05 || right > 0.05
}

let masterImage: NSImage
if isFullBleed(img: rawImg) {
    let size: CGFloat = 1024
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size),
        pixelsHigh: Int(size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    let nsCtx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = nsCtx
    let ctx = nsCtx.cgContext
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // macOS native dock drop shadow
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -12),
        blur: 24,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.40)
    )
    let bodySize: CGFloat = 824
    let margin: CGFloat = (size - bodySize) / 2.0 // 100 pt margin
    let bodyRect = CGRect(x: margin, y: margin + 8, width: bodySize, height: bodySize)
    ctx.draw(cgImage, in: bodyRect)
    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()

    let pngData = rep.representation(using: .png, properties: [:])!
    masterImage = NSImage(data: pngData)!
} else {
    masterImage = rawImg
}

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, px) in specs {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.cgContext.interpolationQuality = .high
    masterImage.draw(in: NSRect(x: 0, y: 0, width: px, height: px), from: .zero, operation: .copy, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fputs("Error generating png for \(name)\n", stderr)
        exit(1)
    }
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}

print("Generated \(outDir) successfully from \(resolvedInput)")
