# WebPDrop

A lightweight macOS utility that converts images to WebP. Drag and drop files onto the window or let it automatically convert screenshots as you take them.

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-blue)
![Swift 6](https://img.shields.io/badge/Swift-6-orange)
![License: MIT](https://img.shields.io/badge/License-MIT-green)

## Why WebP?

macOS Retina screenshots are massive PNGs — a single 5K capture can be 5–10 MB. If you're feeding screenshots to AI coding tools like [Claude Code](https://docs.anthropic.com/en/docs/claude-code), those PNGs eat through your context window fast and can destabilize long sessions. WebP is the best-compressed image format that Claude Code supports, giving you the same visual quality at a fraction of the size and keeping your context lean.

## Features

- **Drag & Drop** — Drop any image (PNG, JPEG, HEIC, TIFF, etc.) onto the window to convert it to WebP
- **Screenshot Auto-Convert** — When enabled, monitors your Desktop and converts new screenshots to WebP as they're taken (existing files are left untouched)
- **Quality Slider** — Adjust WebP compression quality from 0–100%
- **Retina Aware** — Detects HiDPI screenshots and downscales to logical (1x) resolution, since WebP viewers don't honor DPI metadata
- **Color Space Normalization** — Converts Display P3 images to sRGB for consistent rendering across viewers
- **Non-Destructive** — Originals are moved to Trash, not permanently deleted
- **Locale Independent** — Screenshot detection uses macOS metadata (`kMDItemIsScreenCapture`), not filename patterns — works in any language

## Installation

### Build from Source

Requires Xcode and Swift 6.

```bash
git clone https://github.com/mrowlinson/WebPDrop.git
cd WebPDrop
swift build -c release
swift Scripts/package-app.swift
```

The `.app` bundle is created in the project root. Move it to `/Applications` or wherever you like.

### Run Without Packaging

```bash
swift run
```

## Usage

1. Launch WebPDrop
2. Drag image files onto the drop zone — they're converted in place (originals go to Trash)
3. Adjust the quality slider to control compression
4. Toggle **Autoconvert screenshots** to watch your Desktop for new screenshots and convert them automatically

When autoconvert is first enabled, macOS will prompt for Desktop folder access.

## Architecture

```
Sources/WebPDrop/
├── App.swift               # App entry point, window config, menu stripping
├── DropZoneView.swift       # SwiftUI drop zone, quality slider, autoconvert toggle
├── ImageConverter.swift     # Image → WebP conversion (ImageIO + libwebp)
└── ScreenshotMonitor.swift  # Desktop file monitoring via DispatchSource
Scripts/
└── package-app.swift        # Builds .app bundle with generated icon and codesign
```

- **ImageConverter** handles the full pipeline: load via ImageIO, detect Retina DPI, normalize to 8-bit sRGB, encode via libwebp, atomic write + trash original. Each conversion runs inside an `autoreleasepool` to bound CoreGraphics memory.
- **ScreenshotMonitor** uses `DispatchSource.makeFileSystemObjectSource` (not polling) to watch the Desktop directory. New files get a 1-second stabilization delay before conversion to avoid reading partially-written screenshots. Failed conversions are automatically retried on the next directory change.
- Concurrent conversions are capped at 2 to prevent memory spikes from batched Retina images (~59 MB each uncompressed).

## Dependencies

- [Swift-WebP](https://github.com/ainame/Swift-WebP) — Swift wrapper around Google's libwebp
- [libwebp-Xcode](https://github.com/SDWebImage/libwebp-Xcode) — libwebp packaged for Swift Package Manager (transitive)

## License

MIT
