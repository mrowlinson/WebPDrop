import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @State private var status: String = "Drop images here"
    @State private var isTargeted = false
    @State private var isProcessing = false
    @State private var autoconvert = false
    @State private var monitor = ScreenshotMonitor()
    @State private var showPermissionAlert = false
    @State private var statusGeneration = 0

    private static let maxConcurrentConversions = 2

    var body: some View {
        VStack(spacing: 16) {
            dropZone
            qualitySlider
            autoconvertRow
        }
        .padding(20)
        .frame(width: 400)
        .onChange(of: autoconvert) { _, enabled in
            if enabled {
                monitor.start()
            } else {
                monitor.stop()
            }
        }
        .onChange(of: monitor.needsDesktopPermission) { _, needed in
            if needed {
                autoconvert = false
                showPermissionAlert = true
            }
        }
        .alert("Desktop Access Required", isPresented: $showPermissionAlert) {
            Button("Open Privacy Settings") {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!
                )
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("WebPDrop needs access to your Desktop folder to monitor for new screenshots.\n\nGo to Privacy & Security → Files and Folders and enable Desktop access for WebPDrop.")
        }
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                )

            VStack(spacing: 8) {
                Image(systemName: isProcessing ? "arrow.triangle.2.circlepath" : "photo.on.rectangle.angled")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.rotate, isActive: isProcessing)

                Text(status)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(height: 220)
        .onDrop(of: [.image], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
            return true
        }
    }

    private var autoconvertRow: some View {
        HStack {
            Toggle("Autoconvert screenshots", isOn: $autoconvert)
                .toggleStyle(.checkbox)
                .font(.subheadline)
                .focusable(false)
            Spacer()
            if autoconvert && !monitor.lastStatus.isEmpty {
                Text(monitor.lastStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var qualitySlider: some View {
        HStack(spacing: 12) {
            Text("Quality")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Slider(value: $monitor.quality, in: 0...1)
                .disabled(isProcessing)
                .focusable(false)
            Text("\(Int(monitor.quality * 100))%")
                .font(.subheadline.monospacedDigit())
                .frame(width: 36, alignment: .trailing)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        guard !isProcessing else { return }
        isProcessing = true
        status = "Converting..."

        let capturedQuality = monitor.quality

        Task {
            // Collect URLs from providers
            let urls = await withTaskGroup(of: URL?.self, returning: [URL].self) { group in
                for provider in providers {
                    group.addTask {
                        await withCheckedContinuation { continuation in
                            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                                guard let data = item as? Data,
                                      let url = URL(dataRepresentation: data, relativeTo: nil, isAbsolute: true) else {
                                    continuation.resume(returning: nil)
                                    return
                                }
                                continuation.resume(returning: url)
                            }
                        }
                    }
                }
                var result: [URL] = []
                for await url in group {
                    if let url { result.append(url) }
                }
                return result
            }

            // Convert with bounded concurrency
            var converted = 0
            var failed = 0

            await withTaskGroup(of: Bool.self) { group in
                var inflight = 0
                var index = 0

                while index < urls.count {
                    if inflight < Self.maxConcurrentConversions {
                        let url = urls[index]
                        index += 1
                        inflight += 1
                        group.addTask {
                            do {
                                let result = try ImageConverter.convert(fileURL: url, quality: capturedQuality)
                                print("[WebPDrop] Success: \(result.fileName) (\(result.originalSize) -> \(result.newSize) bytes)")
                                return true
                            } catch {
                                print("[WebPDrop] Error: \(error)")
                                return false
                            }
                        }
                    } else {
                        if let success = await group.next() {
                            inflight -= 1
                            if success { converted += 1 } else { failed += 1 }
                        }
                    }
                }

                for await success in group {
                    if success { converted += 1 } else { failed += 1 }
                }
            }

            isProcessing = false
            statusGeneration += 1
            let gen = statusGeneration

            if failed == 0 {
                status = "Done! \(converted) file\(converted == 1 ? "" : "s") converted"
            } else {
                status = "\(converted) converted, \(failed) failed"
            }

            Task {
                try? await Task.sleep(for: .seconds(3))
                if statusGeneration == gen && !isProcessing {
                    status = "Drop images here"
                }
            }
        }
    }
}
