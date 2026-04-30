import Foundation
import Observation

@Observable
@MainActor
final class ScreenshotMonitor {

    var lastStatus: String = ""
    var needsDesktopPermission: Bool = false
    var quality: Double = 0.8

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var processedFiles: Set<String> = []
    private var pendingFiles: Set<String> = []
    private var desktopURL: URL?

    func start() {
        guard source == nil else { return }
        needsDesktopPermission = false

        let desktop = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
        self.desktopURL = desktop

        // Check permission — triggers the TCC prompt if not yet granted
        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: desktop.path)
            processedFiles = Set(contents.filter { Self.isScreenshot(at: desktop.appendingPathComponent($0)) })
        } catch {
            needsDesktopPermission = true
            return
        }

        // Open file descriptor for directory monitoring
        let fd = open(desktop.path, O_EVTONLY)
        guard fd >= 0 else {
            needsDesktopPermission = true
            return
        }
        fileDescriptor = fd

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .global(qos: .utility)
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.handleDirectoryChange() }
        }
        src.setCancelHandler {
            close(fd)
        }
        src.resume()
        source = src
        lastStatus = "Watching Desktop…"
    }

    func stop() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
        processedFiles = []
        pendingFiles = []
        desktopURL = nil
        lastStatus = ""
    }

    // MARK: - Directory Change Handling

    private func handleDirectoryChange() {
        guard let desktop = desktopURL else { return }

        let current: Set<String>
        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: desktop.path)
            current = Set(contents.filter { Self.isScreenshot(at: desktop.appendingPathComponent($0)) })
        } catch {
            needsDesktopPermission = true
            stop()
            return
        }

        let newFiles = current
            .subtracting(processedFiles)
            .subtracting(pendingFiles)

        // Clean up stale entries for deleted files
        processedFiles.formIntersection(current)

        let capturedQuality = quality

        for name in newFiles {
            pendingFiles.insert(name)
            let url = desktop.appendingPathComponent(name)

            Task.detached(priority: .userInitiated) {
                // Wait for macOS to finish writing the screenshot
                try? await Task.sleep(for: .seconds(1))

                // Verify file still exists and has content
                guard FileManager.default.fileExists(atPath: url.path),
                      let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      size > 0 else {
                    await MainActor.run { self.pendingFiles.remove(name) } as Void
                    return
                }

                do {
                    let result = try await ImageConverter.convert(fileURL: url, quality: capturedQuality, stripSpacesFromName: true)
                    await MainActor.run {
                        self.processedFiles.insert(name)
                        self.pendingFiles.remove(name)
                        self.lastStatus = "Converted \(result.fileName)"
                        print("[WebPDrop] Auto-converted: \(result.fileName)")
                    }
                } catch {
                    await MainActor.run {
                        self.pendingFiles.remove(name)
                        self.lastStatus = "Failed: \(name)"
                        print("[WebPDrop] Auto-convert failed: \(error)")
                    }
                }
            }
        }
    }

    // MARK: - Screenshot Detection

    /// Checks the macOS extended attribute `kMDItemIsScreenCapture` to identify
    /// screenshots regardless of locale. Works for any language setting.
    private static func isScreenshot(at url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "png" else { return false }

        let path = url.path
        let bufferSize = getxattr(path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0)
        return bufferSize > 0
    }
}
