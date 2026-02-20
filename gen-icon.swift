#!/usr/bin/env swift
// Generates the OpenClaw Vox app icon (.icns) and menu bar template image.
// Usage: swift gen-icon.swift

import AppKit
import Foundation

// MARK: - Helpers

func createContext(size: Int) -> CGContext {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    return ctx
}

func savePNG(_ ctx: CGContext, to path: String) {
    let image = ctx.makeImage()!
    let url = URL(fileURLWithPath: path)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// MARK: - App icon drawing

func drawAppIcon(ctx: CGContext, size: CGFloat) {
    let s = size
    ctx.saveGState()

    // --- Squircle background ---
    let radius = s * 0.22
    let inset = s * 0.02
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let bgPath = CGMutablePath()
    bgPath.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)

    // Gradient: deep indigo -> dark teal
    let colors = [
        CGColor(red: 0.12, green: 0.10, blue: 0.28, alpha: 1.0),
        CGColor(red: 0.08, green: 0.22, blue: 0.32, alpha: 1.0),
    ]
    ctx.addPath(bgPath)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
    ctx.resetClip()

    // Subtle inner shadow / border
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.08))
    ctx.setLineWidth(s * 0.004)
    ctx.addPath(bgPath)
    ctx.strokePath()

    // --- Claw marks (3 diagonal scratches) ---
    let clawColor = CGColor(red: 0.55, green: 0.85, blue: 1.0, alpha: 0.9)
    ctx.setStrokeColor(clawColor)
    ctx.setLineCap(.round)

    let clawWidth = s * 0.045
    ctx.setLineWidth(clawWidth)

    // Three parallel claw marks, angled ~40 degrees, left-center of icon
    let cx = s * 0.38
    let cy = s * 0.52
    let clawLen = s * 0.30
    let spacing = s * 0.09
    let angle: CGFloat = -0.70  // radians (~40 deg)

    for i in 0..<3 {
        let offset = CGFloat(i - 1) * spacing
        let startX = cx + offset + cos(angle + .pi / 2) * 0
        let startY = cy + clawLen * 0.5 * sin(.pi / 2 - angle)
        let endX = startX + clawLen * cos(angle)
        let endY = startY + clawLen * sin(angle)

        // Draw with a slight curve for organic feel
        let ctrlX = (startX + endX) / 2 + s * 0.02 * CGFloat(i - 1)
        let ctrlY = (startY + endY) / 2 - s * 0.015

        let mark = CGMutablePath()
        // Tapered start
        mark.move(to: CGPoint(x: startX, y: startY))
        mark.addQuadCurve(to: CGPoint(x: endX, y: endY), control: CGPoint(x: ctrlX, y: ctrlY))
        ctx.addPath(mark)
        ctx.strokePath()
    }

    // Claw mark glow
    ctx.setStrokeColor(CGColor(red: 0.55, green: 0.85, blue: 1.0, alpha: 0.25))
    ctx.setLineWidth(clawWidth * 2.5)
    for i in 0..<3 {
        let offset = CGFloat(i - 1) * spacing
        let startX = cx + offset
        let startY = cy + clawLen * 0.5 * sin(.pi / 2 - angle)
        let endX = startX + clawLen * cos(angle)
        let endY = startY + clawLen * sin(angle)
        let ctrlX = (startX + endX) / 2 + s * 0.02 * CGFloat(i - 1)
        let ctrlY = (startY + endY) / 2 - s * 0.015

        let mark = CGMutablePath()
        mark.move(to: CGPoint(x: startX, y: startY))
        mark.addQuadCurve(to: CGPoint(x: endX, y: endY), control: CGPoint(x: ctrlX, y: ctrlY))
        ctx.addPath(mark)
        ctx.strokePath()
    }

    // --- Waveform (right side) ---
    let waveX = s * 0.68
    let waveY = s * 0.50
    let barCount = 5
    let barSpacing = s * 0.042
    let maxBarH = s * 0.28
    let barW = s * 0.028
    let heights: [CGFloat] = [0.35, 0.65, 1.0, 0.75, 0.45]

    for i in 0..<barCount {
        let h = maxBarH * heights[i]
        let x = waveX + CGFloat(i) * barSpacing - (CGFloat(barCount) * barSpacing / 2)
        let y = waveY - h / 2

        let barRect = CGRect(x: x, y: y, width: barW, height: h)
        let barPath = CGPath(roundedRect: barRect, cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil)

        // Bar gradient: cyan to lighter
        ctx.saveGState()
        ctx.addPath(barPath)
        ctx.clip()
        let barColors = [
            CGColor(red: 0.30, green: 0.75, blue: 0.95, alpha: 0.95),
            CGColor(red: 0.65, green: 0.92, blue: 1.0, alpha: 0.95),
        ]
        let barGrad = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: barColors as CFArray,
            locations: [0.0, 1.0]
        )!
        ctx.drawLinearGradient(barGrad, start: CGPoint(x: x, y: y), end: CGPoint(x: x, y: y + h), options: [])
        ctx.restoreGState()
    }

    // Waveform glow
    ctx.saveGState()
    ctx.setFillColor(CGColor(red: 0.40, green: 0.85, blue: 1.0, alpha: 0.08))
    let glowRect = CGRect(x: waveX - s * 0.12, y: waveY - s * 0.18, width: s * 0.24, height: s * 0.36)
    ctx.fillEllipse(in: glowRect)
    ctx.restoreGState()

    ctx.restoreGState()
}

// MARK: - Menu bar template image

func drawMenuBarIconTemplate(ctx: CGContext, size: CGFloat) {
    let s = size
    ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1.0))
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1.0))
    ctx.setLineCap(.round)

    // Small claw marks (left)
    let clawWidth = s * 0.08
    ctx.setLineWidth(clawWidth)

    let cx = s * 0.30
    let cy = s * 0.50
    let clawLen = s * 0.38
    let spacing = s * 0.14
    let angle: CGFloat = -0.70

    for i in 0..<3 {
        let offset = CGFloat(i - 1) * spacing
        let startX = cx + offset
        let startY = cy + clawLen * 0.45
        let endX = startX + clawLen * cos(angle)
        let endY = startY + clawLen * sin(angle)

        let mark = CGMutablePath()
        mark.move(to: CGPoint(x: startX, y: startY))
        mark.addLine(to: CGPoint(x: endX, y: endY))
        ctx.addPath(mark)
        ctx.strokePath()
    }

    // Waveform bars (right)
    let waveX = s * 0.72
    let waveY = s * 0.50
    let barCount = 3
    let barSpacing = s * 0.10
    let maxBarH = s * 0.50
    let barW = s * 0.07
    let heights: [CGFloat] = [0.45, 1.0, 0.55]

    for i in 0..<barCount {
        let h = maxBarH * heights[i]
        let x = waveX + CGFloat(i) * barSpacing - (CGFloat(barCount) * barSpacing / 2)
        let y = waveY - h / 2
        let barRect = CGRect(x: x, y: y, width: barW, height: h)
        let barPath = CGPath(roundedRect: barRect, cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil)
        ctx.addPath(barPath)
        ctx.fillPath()
    }
}

// MARK: - Main

let projectDir = FileManager.default.currentDirectoryPath

// 1. Generate 1024x1024 master icon
print("Drawing 1024x1024 app icon...")
let masterSize = 1024
let masterCtx = createContext(size: masterSize)
drawAppIcon(ctx: masterCtx, size: CGFloat(masterSize))
let masterImage = masterCtx.makeImage()!

// 2. Create .iconset with all required sizes
let iconsetPath = "\(projectDir)/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconsetPath)
try! FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

for (name, px) in sizes {
    let ctx = createContext(size: px)
    // Scale and draw master
    ctx.interpolationQuality = .high
    ctx.draw(masterImage, in: CGRect(x: 0, y: 0, width: px, height: px))
    savePNG(ctx, to: "\(iconsetPath)/\(name).png")
    print("  \(name).png (\(px)x\(px))")
}

// 3. Run iconutil
print("Creating AppIcon.icns...")
let icnsPath = "\(projectDir)/AppIcon.icns"
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconsetPath, "-o", icnsPath]
try! proc.run()
proc.waitUntilExit()

if proc.terminationStatus == 0 {
    print("  -> AppIcon.icns created")
    try? FileManager.default.removeItem(atPath: iconsetPath)
} else {
    print("  iconutil failed with status \(proc.terminationStatus)")
}

// 4. Menu bar template images
print("Drawing menu bar template images...")
let resourcesDir = "\(projectDir)/Sources/OpenClawVox/Resources"
try! FileManager.default.createDirectory(atPath: resourcesDir, withIntermediateDirectories: true)

for scale in [1, 2] {
    let px = 18 * scale
    let ctx = createContext(size: px)
    drawMenuBarIconTemplate(ctx: ctx, size: CGFloat(px))
    let suffix = scale == 1 ? "" : "@2x"
    let path = "\(resourcesDir)/MenuBarIconTemplate\(suffix).png"
    savePNG(ctx, to: path)
    print("  MenuBarIconTemplate\(suffix).png (\(px)x\(px))")
}

print("\nDone!")
