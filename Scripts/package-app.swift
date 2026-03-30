#!/usr/bin/env swift

import Cocoa
import CoreGraphics

// MARK: - Icon Generation

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let bounds = CGRect(x: 0, y: 0, width: size, height: size)
    let inset = size * 0.08
    let rect = bounds.insetBy(dx: inset, dy: inset)
    let cornerRadius = size * 0.22

    // Background gradient — deep blue to teal
    let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(path)
    ctx.clip()

    let colors = [
        CGColor(srgbRed: 0.15, green: 0.35, blue: 0.75, alpha: 1.0),
        CGColor(srgbRed: 0.10, green: 0.65, blue: 0.60, alpha: 1.0)
    ]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: colors as CFArray,
                               locations: [0.0, 1.0])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: rect.minX, y: rect.maxY),
                           end: CGPoint(x: rect.maxX, y: rect.minY),
                           options: [])

    ctx.resetClip()

    // Arrow pointing down into a tray — representing "drop"
    let centerX = size / 2
    let centerY = size / 2

    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95))

    // Down arrow
    let arrowWidth = size * 0.22
    let arrowHeight = size * 0.20
    let arrowHeadWidth = size * 0.35
    let arrowHeadHeight = size * 0.14
    let arrowTop = centerY + size * 0.15

    // Arrow shaft
    let shaftRect = CGRect(x: centerX - arrowWidth / 2,
                           y: arrowTop - arrowHeight - arrowHeadHeight,
                           width: arrowWidth,
                           height: arrowHeight)
    ctx.fill(shaftRect)

    // Arrow head (triangle pointing down)
    let headTop = arrowTop - arrowHeadHeight
    ctx.move(to: CGPoint(x: centerX - arrowHeadWidth / 2, y: headTop))
    ctx.addLine(to: CGPoint(x: centerX + arrowHeadWidth / 2, y: headTop))
    ctx.addLine(to: CGPoint(x: centerX, y: arrowTop))
    ctx.closePath()
    ctx.fillPath()

    // Tray (U-shape at the bottom)
    let trayTop = arrowTop + size * 0.02
    let trayBottom = centerY - size * 0.22
    let trayWidth = size * 0.50
    let trayThickness = size * 0.045

    // Left side of tray
    ctx.fill(CGRect(x: centerX - trayWidth / 2,
                    y: trayBottom,
                    width: trayThickness,
                    height: trayTop - trayBottom))
    // Bottom of tray
    ctx.fill(CGRect(x: centerX - trayWidth / 2,
                    y: trayBottom,
                    width: trayWidth,
                    height: trayThickness))
    // Right side of tray
    ctx.fill(CGRect(x: centerX + trayWidth / 2 - trayThickness,
                    y: trayBottom,
                    width: trayThickness,
                    height: trayTop - trayBottom))

    // "WebP" text at the bottom
    let fontSize = size * 0.13
    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.90)
    ]
    let text = NSAttributedString(string: "WebP", attributes: attributes)
    let textSize = text.size()
    let textOrigin = NSPoint(x: centerX - textSize.width / 2,
                             y: inset + size * 0.06)
    text.draw(at: textOrigin)

    image.unlockFocus()
    return image
}

func createICNS(at path: String) throws {
    let sizes: [(CGFloat, String)] = [
        (16, "16x16"),
        (32, "16x16@2x"),
        (32, "32x32"),
        (64, "32x32@2x"),
        (128, "128x128"),
        (256, "128x128@2x"),
        (256, "256x256"),
        (512, "256x256@2x"),
        (512, "512x512"),
        (1024, "512x512@2x"),
    ]

    let iconsetPath = path + ".iconset"
    try FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

    for (size, name) in sizes {
        let image = drawIcon(size: size)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            continue
        }
        let filePath = "\(iconsetPath)/icon_\(name).png"
        try png.write(to: URL(fileURLWithPath: filePath))
    }

    // Convert iconset to icns
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconsetPath, "-o", path]
    try process.run()
    process.waitUntilExit()

    // Clean up iconset
    try? FileManager.default.removeItem(atPath: iconsetPath)

    if process.terminationStatus != 0 {
        throw NSError(domain: "IconGen", code: 1, userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
    }
}

// MARK: - App Bundle Creation

func createAppBundle() throws {
    let projectDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let buildDir = projectDir.appendingPathComponent(".build/release")
    let binaryPath = buildDir.appendingPathComponent("WebPDrop")
    let appDir = projectDir.appendingPathComponent("WebPDrop.app")
    let contentsDir = appDir.appendingPathComponent("Contents")
    let macOSDir = contentsDir.appendingPathComponent("MacOS")
    let resourcesDir = contentsDir.appendingPathComponent("Resources")

    let fm = FileManager.default

    // Clean previous build
    try? fm.removeItem(at: appDir)

    // Create structure
    try fm.createDirectory(at: macOSDir, withIntermediateDirectories: true)
    try fm.createDirectory(at: resourcesDir, withIntermediateDirectories: true)

    // Copy binary
    guard fm.fileExists(atPath: binaryPath.path) else {
        print("Error: Binary not found at \(binaryPath.path). Run 'swift build -c release' first.")
        exit(1)
    }
    try fm.copyItem(at: binaryPath, to: macOSDir.appendingPathComponent("WebPDrop"))

    // Generate icon
    let icnsPath = resourcesDir.appendingPathComponent("AppIcon.icns").path
    print("Generating app icon...")
    try createICNS(at: icnsPath)

    // Write Info.plist
    let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>CFBundleExecutable</key>
        <string>WebPDrop</string>
        <key>CFBundleIdentifier</key>
        <string>com.webpdrop.app</string>
        <key>CFBundleName</key>
        <string>WebPDrop</string>
        <key>CFBundleDisplayName</key>
        <string>WebPDrop</string>
        <key>CFBundleVersion</key>
        <string>1.0.2</string>
        <key>CFBundleShortVersionString</key>
        <string>1.0.2</string>
        <key>CFBundleIconFile</key>
        <string>AppIcon</string>
        <key>CFBundlePackageType</key>
        <string>APPL</string>
        <key>LSMinimumSystemVersion</key>
        <string>15.0</string>
        <key>NSHighResolutionCapable</key>
        <true/>
        <key>NSDesktopFolderUsageDescription</key>
        <string>WebPDrop monitors your Desktop to automatically convert new screenshots to WebP.</string>
    </dict>
    </plist>
    """
    try plist.write(to: contentsDir.appendingPathComponent("Info.plist"),
                    atomically: true, encoding: .utf8)

    // Ad-hoc sign so macOS accepts the bundle
    let sign = Process()
    sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    sign.arguments = ["--force", "--deep", "--sign", "-", appDir.path]
    try sign.run()
    sign.waitUntilExit()
    guard sign.terminationStatus == 0 else {
        throw NSError(domain: "Codesign", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "codesign failed"])
    }

    print("App bundle created at: \(appDir.path)")
}

// MARK: - Main

do {
    try createAppBundle()
} catch {
    print("Error: \(error.localizedDescription)")
    exit(1)
}
