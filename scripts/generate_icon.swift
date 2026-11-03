import AppKit
import CoreImage

let args = CommandLine.arguments
let outDir = args.count > 1 ? args[1] : "build/AppIcon.iconset"
let previewPath = args.count > 2 ? args[2] : "assets/icon.png"

// Create a rounded regular polygon CGPath (for the rounded yellow hexagon)
func roundedPolygonPath(center: CGPoint, radius: CGFloat, sides: Int, cornerRadius: CGFloat, rotationOffset: CGFloat = .pi / 2.0) -> CGPath {
    var vertices: [CGPoint] = []
    for i in 0..<sides {
        let angle = rotationOffset + CGFloat(i) * (2.0 * .pi / CGFloat(sides))
        vertices.append(CGPoint(
            x: center.x + radius * cos(angle),
            y: center.y + radius * sin(angle)
        ))
    }
    let path = CGMutablePath()
    let mid01 = CGPoint(x: (vertices[0].x + vertices[1].x) * 0.5, y: (vertices[0].y + vertices[1].y) * 0.5)
    path.move(to: mid01)
    for i in 0..<sides {
        let p1 = vertices[(i + 1) % sides]
        let p2 = vertices[(i + 2) % sides]
        path.addArc(tangent1End: p1, tangent2End: p2, radius: cornerRadius)
    }
    path.closeSubpath()
    return path
}

// Draw a directional gradient stroke along a path (Apple Liquid Glass specular rim)
func drawDirectionalRim(ctx: CGContext, path: CGPath, lineWidth: CGFloat, start: CGPoint, end: CGPoint, colors: [CGColor], locations: [CGFloat]) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setLineWidth(lineWidth)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let grad = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations)!
    ctx.drawLinearGradient(grad, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func renderIcon(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
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
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let s = CGFloat(size)
    let u = s / 1024.0

    // 1. Apple macOS Tahoe Squircle Geometry (exact match to Shortcuts.app)
    let margin = 100.0 * u
    let bodySize = s - margin * 2.0
    let bodyRect = CGRect(x: margin, y: margin, width: bodySize, height: bodySize)
    let bodyRadius = bodySize * 0.225
    let squirclePath = CGPath(roundedRect: bodyRect, cornerWidth: bodyRadius, cornerHeight: bodyRadius, transform: nil)

    // External drop shadow under squircle
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -10.0 * u),
        blur: 22.0 * u,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.42)
    )
    ctx.setFillColor(CGColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1.0))
    ctx.addPath(squirclePath)
    ctx.fillPath()
    ctx.restoreGState()

    // Clip everything inside the squircle
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    // Deep near-black matte-charcoal squircle background (Shortcuts.app dark plate)
    let bgColors = [
        CGColor(red: 0.110, green: 0.110, blue: 0.118, alpha: 1.0),
        CGColor(red: 0.055, green: 0.055, blue: 0.060, alpha: 1.0)
    ] as CFArray
    let bgGrad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(
        bgGrad,
        start: CGPoint(x: s * 0.5, y: bodyRect.maxY),
        end: CGPoint(x: s * 0.5, y: bodyRect.minY),
        options: []
    )

    // Soft diffused inner cushion bevel along the top & bottom edges of the dark squircle
    ctx.saveGState()
    let outerFrame = bodyRect.insetBy(dx: -60.0 * u, dy: -60.0 * u)
    let cutoutPath = CGMutablePath()
    cutoutPath.addRect(outerFrame)
    cutoutPath.addPath(squirclePath)
    ctx.setShadow(
        offset: CGSize(width: 0, height: -6.0 * u),
        blur: 24.0 * u,
        color: CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.25)
    )
    ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))
    ctx.addPath(cutoutPath)
    ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()

    // Crisp 1.5px top-down rim on the squircle itself
    drawDirectionalRim(
        ctx: ctx,
        path: squirclePath,
        lineWidth: 3.5 * u,
        start: CGPoint(x: s * 0.5, y: bodyRect.maxY),
        end: CGPoint(x: s * 0.5, y: bodyRect.minY),
        colors: [
            CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.32),
            CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.04),
            CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.14)
        ],
        locations: [0.0, 0.65, 1.0]
    )

    let center = CGPoint(x: s * 0.5, y: s * 0.5)

    // 2. LAYER 1: Clean, Single Rounded Yellow Hexagon (CrossOver Symbol)
    let hexRadius = 268.0 * u
    let hexCorner = 58.0 * u
    let hexPath = roundedPolygonPath(center: center, radius: hexRadius, sides: 6, cornerRadius: hexCorner)

    // Soft ambient warm-yellow bloom on the dark plate underneath the hexagon
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -10.0 * u),
        blur: 32.0 * u,
        color: CGColor(red: 1.0, green: 0.72, blue: 0.0, alpha: 0.24)
    )
    ctx.setFillColor(CGColor(red: 1.0, green: 0.78, blue: 0.02, alpha: 1.0))
    ctx.addPath(hexPath)
    ctx.fillPath()
    ctx.restoreGState()

    // Fill Yellow Hexagon with smooth, rich Apple Liquid Glass yellow-amber gradient
    ctx.saveGState()
    ctx.addPath(hexPath)
    ctx.clip()
    let hexColors = [
        CGColor(red: 1.00, green: 0.92, blue: 0.18, alpha: 1.0), // Top-left sun yellow
        CGColor(red: 0.99, green: 0.74, blue: 0.02, alpha: 1.0), // Mid golden yellow
        CGColor(red: 0.88, green: 0.48, blue: 0.00, alpha: 1.0)  // Bottom-right rich warm amber
    ] as CFArray
    let hexGrad = CGGradient(colorsSpace: colorSpace, colors: hexColors, locations: [0.0, 0.52, 1.0])!
    ctx.drawLinearGradient(
        hexGrad,
        start: CGPoint(x: center.x - 190.0 * u, y: center.y + 220.0 * u),
        end: CGPoint(x: center.x + 210.0 * u, y: center.y - 230.0 * u),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // Soft inner cushion volume on the yellow hexagon
    ctx.saveGState()
    let hexOuter = bodyRect.insetBy(dx: -80.0 * u, dy: -80.0 * u)
    let hexCutout = CGMutablePath()
    hexCutout.addRect(hexOuter)
    hexCutout.addPath(hexPath)
    ctx.setShadow(
        offset: CGSize(width: 6.0 * u, height: -8.0 * u),
        blur: 22.0 * u,
        color: CGColor(red: 1.0, green: 0.98, blue: 0.75, alpha: 0.55)
    )
    ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))
    ctx.addPath(hexCutout)
    ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()
    ctx.restoreGState() // End hex clip

    // Directional Apple Liquid Glass specular rim around the Yellow Hexagon
    drawDirectionalRim(
        ctx: ctx,
        path: hexPath,
        lineWidth: 4.0 * u,
        start: CGPoint(x: center.x - 200.0 * u, y: center.y + 230.0 * u),
        end: CGPoint(x: center.x + 200.0 * u, y: center.y - 230.0 * u),
        colors: [
            CGColor(red: 1.0, green: 0.99, blue: 0.86, alpha: 0.92),
            CGColor(red: 1.0, green: 0.85, blue: 0.35, alpha: 0.25),
            CGColor(red: 1.0, green: 0.92, blue: 0.55, alpha: 0.65)
        ],
        locations: [0.0, 0.6, 1.0]
    )

    // 3. LAYER 2: Frosted Liquid Glass Band-Aid Overlapping the Yellow Hexagon
    let bandAngle: CGFloat = .pi * 0.215 // ~38.7 degrees
    let bandWidth: CGFloat = 600.0 * u
    let bandHeight: CGFloat = 212.0 * u
    let bandRadius: CGFloat = bandHeight * 0.5

    var bandTransform = CGAffineTransform(translationX: center.x, y: center.y)
        .rotated(by: bandAngle)
    let localBandRect = CGRect(x: -bandWidth * 0.5, y: -bandHeight * 0.5, width: bandWidth, height: bandHeight)
    let bandPath = CGPath(roundedRect: localBandRect, cornerWidth: bandRadius, cornerHeight: bandRadius, transform: &bandTransform)

    let padWidth: CGFloat = 192.0 * u
    let padHeight: CGFloat = 148.0 * u
    let padRadius: CGFloat = 40.0 * u
    let localPadRect = CGRect(x: -padWidth * 0.5, y: -padHeight * 0.5, width: padWidth, height: padHeight)
    let padPath = CGPath(roundedRect: localPadRect, cornerWidth: padRadius, cornerHeight: padRadius, transform: &bandTransform)

    // Soft elevation shadow cast by the Band-Aid onto the Yellow Hexagon & dark plate
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -14.0 * u),
        blur: 28.0 * u,
        color: CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.42)
    )
    ctx.setFillColor(CGColor(red: 0.2, green: 0.2, blue: 0.22, alpha: 0.15))
    ctx.addPath(bandPath)
    ctx.fillPath()
    ctx.restoreGState()

    // Clip to Band-Aid pill
    ctx.saveGState()
    ctx.addPath(bandPath)
    ctx.clip()

    // A) Outside the hexagon (the two tips over the dark charcoal background):
    let tipGlassColors = [
        CGColor(red: 0.42, green: 0.43, blue: 0.47, alpha: 0.72),
        CGColor(red: 0.24, green: 0.25, blue: 0.28, alpha: 0.68)
    ] as CFArray
    let tipGlassGrad = CGGradient(colorsSpace: colorSpace, colors: tipGlassColors, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(
        tipGlassGrad,
        start: CGPoint(x: center.x - 220.0 * u, y: center.y + 220.0 * u),
        end: CGPoint(x: center.x + 220.0 * u, y: center.y - 220.0 * u),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // B) Inside the overlap with the Yellow Hexagon (Shortcuts.app translucent overlap physics!)
    ctx.saveGState()
    var refractTransform = CGAffineTransform(translationX: center.x, y: center.y)
        .scaledBy(x: 1.015, y: 1.015)
        .translatedBy(x: -center.x, y: -center.y)
    if let refractedHex = hexPath.copy(using: &refractTransform) {
        ctx.addPath(refractedHex)
        ctx.clip()

        let overlapColors = [
            CGColor(red: 1.00, green: 0.96, blue: 0.68, alpha: 0.92), // Frosted creamy gold top-left
            CGColor(red: 0.98, green: 0.82, blue: 0.34, alpha: 0.88), // Warm frosted amber-gold center
            CGColor(red: 0.92, green: 0.64, blue: 0.16, alpha: 0.86)  // Deep frosted honey bottom-right
        ] as CFArray
        let overlapGrad = CGGradient(colorsSpace: colorSpace, colors: overlapColors, locations: [0.0, 0.55, 1.0])!
        ctx.drawLinearGradient(
            overlapGrad,
            start: CGPoint(x: center.x - 190.0 * u, y: center.y + 210.0 * u),
            end: CGPoint(x: center.x + 190.0 * u, y: center.y - 210.0 * u),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )

        // Crisp refracted contour line of the underlying hexagon visible through the glass band-aid
        drawDirectionalRim(
            ctx: ctx,
            path: refractedHex,
            lineWidth: 3.5 * u,
            start: CGPoint(x: center.x - 200.0 * u, y: center.y + 220.0 * u),
            end: CGPoint(x: center.x + 200.0 * u, y: center.y - 220.0 * u),
            colors: [
                CGColor(red: 1.0, green: 0.99, blue: 0.88, alpha: 0.65),
                CGColor(red: 1.0, green: 0.88, blue: 0.45, alpha: 0.30)
            ],
            locations: [0.0, 1.0]
        )
    }
    ctx.restoreGState()

    // Soft inner cushion highlight inside the Band-Aid pill
    ctx.saveGState()
    let bandOuter = bodyRect.insetBy(dx: -80.0 * u, dy: -80.0 * u)
    let bandCutout = CGMutablePath()
    bandCutout.addRect(bandOuter)
    bandCutout.addPath(bandPath)
    ctx.setShadow(
        offset: CGSize(width: 4.0 * u, height: -6.0 * u),
        blur: 18.0 * u,
        color: CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.42)
    )
    ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))
    ctx.addPath(bandCutout)
    ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()

    // Minimalist frosted perforation dots on the two wings (2x3 grid on each side)
    let dotRadius: CGFloat = 8.0 * u
    let xOffsets: [CGFloat] = [-192.0 * u, -148.0 * u, 148.0 * u, 192.0 * u]
    let yOffsets: [CGFloat] = [-42.0 * u, 0.0, 42.0 * u]
    for dx in xOffsets {
        for dy in yOffsets {
            let pt = CGPoint(x: dx, y: dy).applying(bandTransform)
            let dotRect = CGRect(x: pt.x - dotRadius, y: pt.y - dotRadius, width: dotRadius * 2.0, height: dotRadius * 2.0)
            ctx.saveGState()
            ctx.setFillColor(CGColor(red: 0.55, green: 0.36, blue: 0.0, alpha: 0.24))
            ctx.fillEllipse(in: dotRect)
            ctx.setStrokeColor(CGColor(red: 1.0, green: 0.98, blue: 0.88, alpha: 0.55))
            ctx.setLineWidth(1.5 * u)
            ctx.strokeEllipse(in: dotRect)
            ctx.restoreGState()
        }
    }

    // Center Frosted Gauze Pad (second elevated translucent glass tile)
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -5.0 * u),
        blur: 14.0 * u,
        color: CGColor(red: 0.55, green: 0.32, blue: 0.0, alpha: 0.22)
    )
    ctx.addPath(padPath)
    ctx.clip()
    let padColors = [
        CGColor(red: 1.00, green: 0.99, blue: 0.92, alpha: 0.62),
        CGColor(red: 1.00, green: 0.93, blue: 0.72, alpha: 0.42)
    ] as CFArray
    let padGrad = CGGradient(colorsSpace: colorSpace, colors: padColors, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(
        padGrad,
        start: CGPoint(x: center.x - 80.0 * u, y: center.y + 90.0 * u),
        end: CGPoint(x: center.x + 80.0 * u, y: center.y - 90.0 * u),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    ctx.restoreGState()

    // Directional specular rim around the center gauze pad
    drawDirectionalRim(
        ctx: ctx,
        path: padPath,
        lineWidth: 3.0 * u,
        start: CGPoint(x: center.x - 90.0 * u, y: center.y + 90.0 * u),
        end: CGPoint(x: center.x + 90.0 * u, y: center.y - 90.0 * u),
        colors: [
            CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.88),
            CGColor(red: 1.0, green: 0.95, blue: 0.78, alpha: 0.28),
            CGColor(red: 1.0, green: 0.98, blue: 0.88, alpha: 0.55)
        ],
        locations: [0.0, 0.6, 1.0]
    )

    // Directional Apple Liquid Glass specular rim around the outer Band-Aid pill
    drawDirectionalRim(
        ctx: ctx,
        path: bandPath,
        lineWidth: 4.5 * u,
        start: CGPoint(x: center.x - 220.0 * u, y: center.y + 220.0 * u),
        end: CGPoint(x: center.x + 220.0 * u, y: center.y - 220.0 * u),
        colors: [
            CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.95),
            CGColor(red: 1.0, green: 0.96, blue: 0.82, alpha: 0.30),
            CGColor(red: 1.0, green: 0.98, blue: 0.90, alpha: 0.70)
        ],
        locations: [0.0, 0.6, 1.0]
    )

    ctx.restoreGState() // End Band-Aid clip
    ctx.restoreGState() // End Squircle clip

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let masterData = renderIcon(size: 1024)
try? FileManager.default.createDirectory(atPath: (previewPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
try! masterData.write(to: URL(fileURLWithPath: previewPath))

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
    let data = renderIcon(size: px)
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}
print("Generated HexAid Liquid Glass iconset successfully.")
