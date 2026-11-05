import AppKit

let args = CommandLine.arguments
let outDir = args.count > 1 ? args[1] : "build/AppIcon.iconset"
let inputIcon = args.count > 2 ? args[2] : "assets/icon.png"

let fm = FileManager.default
try? fm.removeItem(atPath: outDir)
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

guard let srcImage = NSImage(contentsOfFile: inputIcon) else {
    fputs("Error: Could not load source icon at \(inputIcon)\n", stderr)
    exit(1)
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
    srcImage.draw(in: NSRect(x: 0, y: 0, width: px, height: px), from: .zero, operation: .copy, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fputs("Error generating png for \(name)\n", stderr)
        exit(1)
    }
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}

print("Generated \(outDir) successfully from \(inputIcon)")
