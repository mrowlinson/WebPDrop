import Foundation
import AppKit
import CoreGraphics
import ImageIO
import WebP

enum ConversionError: LocalizedError {
    case alreadyWebP
    case cannotCreateSource
    case cannotCreateImage
    case encodeFailed(String)
    case writeFailed
    case trashFailed
    case renameFailed

    var errorDescription: String? {
        switch self {
        case .alreadyWebP: "File is already WebP"
        case .cannotCreateSource: "Failed to read image file"
        case .cannotCreateImage: "Failed to decode image"
        case .encodeFailed(let msg): "WebP encode failed: \(msg)"
        case .writeFailed: "Failed to write WebP file"
        case .trashFailed: "Failed to trash original file"
        case .renameFailed: "Failed to rename output file"
        }
    }
}

struct ConversionResult {
    let fileName: String
    let originalSize: Int64
    let newSize: Int64
}

enum ImageConverter {

    static func convert(fileURL: URL, quality: Double, stripSpacesFromName: Bool = false) async throws -> ConversionResult {
        // Skip files that are already WebP
        if fileURL.pathExtension.lowercased() == "webp" {
            throw ConversionError.alreadyWebP
        }

        let fm = FileManager.default
        let originalSize = Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)

        let directory = fileURL.deletingLastPathComponent()
        let stem = fileURL.deletingPathExtension().lastPathComponent
        let outputStem = stripSpacesFromName
            ? String(stem.unicodeScalars.filter { !CharacterSet.whitespaces.contains($0) })
            : stem
        let finalURL = directory.appendingPathComponent("\(outputStem).webp")
        let tempURL = directory.appendingPathComponent("\(outputStem).webp.tmp")

        // Wrap encode in autoreleasepool to flush CGImage/CGContext memory immediately
        // after each conversion instead of deferring to the end of the task
        try autoreleasepool {
            // Load image via ImageIO (supports all macOS image formats)
            guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
                throw ConversionError.cannotCreateSource
            }
            guard let cgImageRaw = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw ConversionError.cannotCreateImage
            }

            // Read DPI from source image for Retina awareness
            let scaleFactor: Double
            if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
               let dx = props[kCGImagePropertyDPIWidth] as? Double,
               dx > 72 {
                scaleFactor = dx / 72.0
            } else {
                scaleFactor = 1.0
            }

            // Normalize to 8-bit sRGB RGBA and downscale Retina images to logical size.
            // macOS viewers don't honor EXIF DPI for WebP, so we must resize to 1x.
            let targetWidth: Int
            let targetHeight: Int
            if scaleFactor > 1.0 {
                targetWidth = Int(Double(cgImageRaw.width) / scaleFactor)
                targetHeight = Int(Double(cgImageRaw.height) / scaleFactor)
            } else {
                targetWidth = cgImageRaw.width
                targetHeight = cgImageRaw.height
            }

            guard let cgImage = normalizeCGImage(cgImageRaw, width: targetWidth, height: targetHeight) else {
                throw ConversionError.cannotCreateImage
            }

            // Encode to WebP using libwebp (quality 0-100)
            let webpQuality = Float(quality * 100)
            let webpData: Data
            do {
                let encoder = WebPEncoder()
                webpData = try encoder.encode(
                    cgImage,
                    config: .preset(.photo, quality: webpQuality)
                )
            } catch {
                throw ConversionError.encodeFailed(error.localizedDescription)
            }

            do {
                try webpData.write(to: tempURL)
            } catch {
                throw ConversionError.writeFailed
            }
        }

        // Trash original file via NSWorkspace.recycle, which routes through Finder
        // and correctly handles iCloud Drive / FileProvider-managed paths
        // (FileManager.trashItem can permanently delete iCloud-synced files).
        do {
            try await recycle(fileURL)
        } catch {
            try? fm.removeItem(at: tempURL)
            throw ConversionError.trashFailed
        }

        // Move temp to final
        try? fm.removeItem(at: finalURL)
        do {
            try fm.moveItem(at: tempURL, to: finalURL)
        } catch {
            throw ConversionError.renameFailed
        }

        let newSize = Int64((try? finalURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)

        return ConversionResult(
            fileName: "\(outputStem).webp",
            originalSize: originalSize,
            newSize: newSize
        )
    }

    // MARK: - Trash

    private static func recycle(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.recycle([url]) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    // MARK: - Image Normalization

    /// Redraws into 8-bit sRGB RGBA at the given dimensions.
    /// Handles color space conversion (P3 → sRGB) and Retina downscaling in one pass.
    private static func normalizeCGImage(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        return context.makeImage()
    }

}
