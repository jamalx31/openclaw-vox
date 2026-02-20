#!/usr/bin/env swift
// Processes unnamed.jpg into AppIcon.icns and menu bar template images.
import AppKit
import Foundation

let projectDir = FileManager.default.currentDirectoryPath
let srcPath = "\(projectDir)/unnamed.jpg"

guard let srcImage = NSImage(contentsOfFile: srcPath) else {
    fatalError("Cannot load \(srcPath)")
}

let srcRep = srcImage.representations.first!
let srcW = srcRep.pixelsWide
let srcH = srcRep.pixelsHigh
print("Source: \(srcW)x\(srcH)")

// MARK: - Helpers

func createContext(size: Int) -> CGContext {
    let cs = CGColorSpaceCreateDeviceRGB()
    return CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

func savePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// MARK: - Create 1024x1024 square icon

// Center-crop to square, then composite onto 1024x1024 with dark background
let squareSide = min(srcW, srcH)  // 796
let cropX = (srcW - squareSide) / 2
let cropY = (srcH - squareSide) / 2

let bitmapRep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: srcW, pixelsHigh: srcH,
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
srcImage.draw(in: NSRect(x: 0, y: 0, width: srcW, height: srcH))
NSGraphicsContext.restoreGraphicsState()

let fullCG = bitmapRep.cgImage!
let croppedCG = fullCG.cropping(to: CGRect(x: cropX, y: cropY, width: squareSide, height: squareSide))!

// Draw onto 1024x1024 canvas with dark background matching the image corners
let masterSize = 1024
let ctx = createContext(size: masterSize)
ctx.setFillColor(CGColor(red: 0.02, green: 0.01, blue: 0.03, alpha: 1.0))
ctx.fill(CGRect(x: 0, y: 0, width: masterSize, height: masterSize))

// Draw the cropped image centered, scaled to fill
let scale = CGFloat(masterSize) / CGFloat(squareSide)
let drawSize = Int(CGFloat(squareSide) * scale)
let offset = (masterSize - drawSize) / 2
ctx.interpolationQuality = .high
ctx.draw(croppedCG, in: CGRect(x: offset, y: offset, width: drawSize, height: drawSize))

let masterImage = ctx.makeImage()!

// MARK: - Create .iconset

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

print("Generating iconset...")
for (name, px) in sizes {
    let sizeCtx = createContext(size: px)
    sizeCtx.interpolationQuality = .high
    sizeCtx.draw(masterImage, in: CGRect(x: 0, y: 0, width: px, height: px))
    savePNG(sizeCtx.makeImage()!, to: "\(iconsetPath)/\(name).png")
    print("  \(name).png")
}

// MARK: - iconutil

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

// MARK: - Menu bar template (silhouette of the character)
// Create a simplified monochrome version for the menu bar

print("Creating menu bar template images...")
let resourcesDir = "\(projectDir)/Sources/OpenClawVox/Resources"
try! FileManager.default.createDirectory(atPath: resourcesDir, withIntermediateDirectories: true)

// For the menu bar, create a small silhouette version of the character
// We'll threshold the image to create a black template on transparent background
for scaleFactor in [1, 2] {
    let px = 18 * scaleFactor
    let menuCtx = createContext(size: px)

    // Draw the character image scaled down
    menuCtx.interpolationQuality = .high
    menuCtx.draw(croppedCG, in: CGRect(x: 0, y: 0, width: px, height: px))

    // Convert to silhouette: read pixels, make non-dark pixels black, dark pixels transparent
    let menuImage = menuCtx.makeImage()!
    let silCtx = createContext(size: px)
    let data = menuImage.dataProvider!.data! as Data
    let silData = UnsafeMutablePointer<UInt8>.allocate(capacity: px * px * 4)

    for y in 0..<px {
        for x in 0..<px {
            let i = (y * px + x) * 4
            let r = data[i]
            let g = data[i + 1]
            let b = data[i + 2]
            let brightness = (Int(r) + Int(g) + Int(b)) / 3

            if brightness > 35 {
                // Visible part of the character -> solid black
                silData[i] = 0       // R
                silData[i + 1] = 0   // G
                silData[i + 2] = 0   // B
                silData[i + 3] = UInt8(min(255, brightness + 60))  // A based on brightness
            } else {
                // Background -> transparent
                silData[i] = 0
                silData[i + 1] = 0
                silData[i + 2] = 0
                silData[i + 3] = 0
            }
        }
    }

    let cs = CGColorSpaceCreateDeviceRGB()
    let silImage = CGContext(
        data: silData, width: px, height: px,
        bitsPerComponent: 8, bytesPerRow: px * 4, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!.makeImage()!

    let suffix = scaleFactor == 1 ? "" : "@2x"
    savePNG(silImage, to: "\(resourcesDir)/MenuBarIconTemplate\(suffix).png")
    print("  MenuBarIconTemplate\(suffix).png (\(px)x\(px))")
    silData.deallocate()
}

print("\nDone!")
