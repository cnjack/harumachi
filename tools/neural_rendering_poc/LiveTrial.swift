// Live capture/processing telemetry plus isolated window compatibility experiments.
// RenderEngine, MLX model and the original capture/processing queues are unchanged.
import AppKit
import Foundation
import CoreVideo
import ScreenCore

final class LiveMetrics: @unchecked Sendable {
    static let shared = LiveMetrics()
    private let lock = NSLock()
    private var rows: [Double: [String: Double]] = [:]
    private var enabled = false
    private var start = 0.0
    private var end = 0.0
    private var unixOffset = 0.0
    private var duplicatePresents = 0
    private var observations = [[String: Double]]()

    func begin(start: Double, end: Double) {
        lock.lock(); defer { lock.unlock() }
        rows = [:]; observations = []; self.start = start; self.end = end
        unixOffset = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
        duplicatePresents = 0; enabled = true
    }
    func received(_ frame: CapturedFrame) {
        lock.lock(); let active = enabled; let a = start; let b = end; lock.unlock()
        let now = Date().timeIntervalSince1970
        guard active, now >= a - 1, now <= b else { return }
        let word = Self.decode(frame.pixels)
        lock.lock(); defer { lock.unlock() }
        rows[frame.capturedAt] = ["capture_host": frame.capturedAt, "received_host": ProcessInfo.processInfo.systemUptime,
            "source_stamp": word,
            "source_width": Double(CVPixelBufferGetWidth(frame.pixels)), "source_height": Double(CVPixelBufferGetHeight(frame.pixels))]
    }
    static func decode(_ pixels: CVPixelBuffer) -> Double {
        let width = CVPixelBufferGetWidth(pixels), height = CVPixelBufferGetHeight(pixels)
        let scale = Double(width) / 1280.0
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        let base = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(pixels)
        let y = min(height - 1, max(0, Int(Double(height) - 18 * scale)))
        var word: UInt32 = 0
        for bit in 0..<24 {
            let x = min(width - 1, Int((64 + (Double(bit) + 0.5) * 8) * scale))
            let p = y * stride + x * 4
            word = (word << 1) | (Int(base[p]) + Int(base[p + 1]) + Int(base[p + 2]) > 384 ? 1 : 0)
        }
        CVPixelBufferUnlockBaseAddress(pixels, .readOnly)
        return word >> 16 == 0xA5 ? Double(word & 65535) : -1
    }
    func observed(_ pixels: CVPixelBuffer, host: Double) {
        lock.lock(); let active = enabled; let a = start; let b = end; lock.unlock()
        let now = Date().timeIntervalSince1970
        guard active, now >= a - 1, now <= b else { return }
        let stamp = Self.decode(pixels)
        lock.lock(); defer { lock.unlock() }
        observations.append(["stamp": stamp, "host": host, "unix": host + unixOffset,
            "width": Double(CVPixelBufferGetWidth(pixels)), "height": Double(CVPixelBufferGetHeight(pixels))])
    }
    func processed(_ frame: RenderedFrame, dropped: Int) {
        lock.lock(); defer { lock.unlock() }
        guard enabled, rows[frame.capturedAt] != nil else { return }
        rows[frame.capturedAt]?["processed_host"] = ProcessInfo.processInfo.systemUptime
        rows[frame.capturedAt]?["processing_ms"] = frame.milliseconds
        rows[frame.capturedAt]?["dropped_cumulative"] = Double(dropped)
        rows[frame.capturedAt]?["neural"] = frame.neural ? 1 : 0
    }
    func presented(source: Double, host: Double, submitted: Double, window: Double) {
        lock.lock(); defer { lock.unlock() }
        guard enabled, rows[source] != nil else { return }
        rows[source]?["present_callback_host"] = ProcessInfo.processInfo.systemUptime
        rows[source]?["present_raw_host"] = host
        guard host > 0 else { return }
        if rows[source]?["presented_host"] != nil { duplicatePresents += 1; return }
        rows[source]?["submitted_host"] = submitted
        rows[source]?["presented_host"] = host
        rows[source]?["presented_unix"] = host + unixOffset
        rows[source]?["presented_window"] = window
    }
    @MainActor func submitted(source: Double, host: Double) {
        lock.lock(); defer { lock.unlock() }
        guard enabled, rows[source] != nil else { return }
        rows[source]?["submitted_host"] = host
        if let window = NSApplication.shared.windows.first(where: { $0.title.isEmpty && $0.level.rawValue == 26 }) {
            rows[source]?["window_visible"] = window.isVisible ? 1 : 0
            rows[source]?["window_occlusion"] = Double(window.occlusionState.rawValue)
            rows[source]?["window_alpha"] = window.alphaValue
            rows[source]?["view_wants_layer"] = window.contentView?.wantsLayer == true ? 1 : 0
            rows[source]?["view_hidden"] = window.contentView?.isHiddenOrHasHiddenAncestor == true ? 1 : 0
            rows[source]?["layer_hidden"] = window.contentView?.layer?.isHidden == true ? 1 : 0
            rows[source]?["layer_opacity"] = Double(window.contentView?.layer?.opacity ?? -1)
            rows[source]?["layer_width"] = window.contentView?.layer?.bounds.width ?? -1
        }
    }
    func completed(source: Double, gpuEnd: Double) {
        lock.lock(); defer { lock.unlock() }
        guard enabled, rows[source] != nil else { return }
        rows[source]?["gpu_completed_host"] = gpuEnd
    }
    func finish() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        enabled = false
        return ["start_unix": start, "end_unix": end, "unix_minus_host": unixOffset,
            "duplicate_presentations": duplicatePresents,
            "frames": rows.values.sorted { $0["capture_host"]! < $1["capture_host"]! }, "display_observations": observations,
            "scope": "Actual app capture and inference; first positive Metal presentation per source frame. presented_window identifies preview versus overlay. Zero timestamps are excluded, never replaced with GPU completion. No hardware input-to-photon claim."]
    }
}

@MainActor
enum LiveTrial {
    static var active: Bool { Diagnostics.argument("--live-trial") != nil }
    static func write(_ value: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }
    static func run(model: AppModel, controls: NSWindow) async {
        guard let directory = Diagnostics.argument("--live-trial") else { return }
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        let defaults = UserDefaults.standard.data(forKey: "renderSettings")
        let probe = VisibleProbe()
        defer {
            if let defaults { UserDefaults.standard.set(defaults, forKey: "renderSettings") }
            else { UserDefaults.standard.removeObject(forKey: "renderSettings") }
        }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try write(["model_loaded": model.modelLoaded, "screen_permission_preflight": CGPreflightScreenCaptureAccess(), "pid": ProcessInfo.processInfo.processIdentifier], to: root.appendingPathComponent("app-ready.json"))
            var last = ""
            while !Task.isCancelled {
                try await Task.sleep(for: .milliseconds(100))
                let file = root.appendingPathComponent("app-command.json")
                guard let data = try? Data(contentsOf: file),
                      let command = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let id = command["id"] as? String, id != last else { continue }
                last = id
                let action = command["action"] as? String ?? "configure"
                if action == "quit" {
                    await model.stop(); await probe.stop()
                    if let defaults { UserDefaults.standard.set(defaults, forKey: "renderSettings") }
                    else { UserDefaults.standard.removeObject(forKey: "renderSettings") }
                    exit(0)
                }
                if action == "configure" {
                    await model.stop(); await probe.stop()
                    await model.refreshSources()
                    guard let source = model.sources.first(where: { $0.window?.title?.hasPrefix("Harumachi Neural Live Trial") == true }) else {
                        throw PortError.message(model.error ?? "Trial game window not found. Grant screen recording access if requested, then retry.")
                    }
                    if command["mode"] as? String != "baseline" {
                        var settings = RenderSettings()
                        settings.processingLongEdge = command["width"] as? Int ?? 512
                        settings.captureFPS = command["fps"] as? Int ?? 60
                        settings.neuralEnabled = command["mode"] as? String != "bypass"
                        settings.split = Float(command["split"] as? Double ?? 0)
                        settings.sanitize()
                        model.settings = settings; model.sourceID = source.id
                        await model.start()
                        guard model.running else { throw PortError.message(model.error ?? "Capture failed") }
                        model.overlayEnabled = true
                    }
                    // Keep the real app preview beside the game on the existing display.
                    controls.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
                    controls.orderFrontRegardless()
                    try await probe.start(source: source)
                    try write(["id": id, "configured": true, "running": model.running,
                        "screens": NSScreen.screens.map { ["frame": NSStringFromRect($0.frame), "scale": $0.backingScaleFactor] },
                        "windows": NSApplication.shared.windows.map { window in
                            ["title": window.title, "id": window.windowNumber, "frame": NSStringFromRect(window.frame), "visible": window.isVisible,
                             "occlusion": window.occlusionState.rawValue, "level": window.level.rawValue,
                             "content_bounds": NSStringFromRect(window.contentView?.bounds ?? .zero)] as [String: Any]
                        }], to: root.appendingPathComponent("app-ack.json"))
                } else if action == "measure", let start = command["start"] as? Double, let end = command["end"] as? Double {
                    LiveMetrics.shared.begin(start: start, end: end)
                    try write(["id": id, "measuring": true], to: root.appendingPathComponent("app-ack.json"))
                    while Date().timeIntervalSince1970 < end + 0.5 { try await Task.sleep(for: .milliseconds(100)) }
                    var report = LiveMetrics.shared.finish()
                    report["presentation_targets"] = ["preview": controls.windowNumber,
                        "overlay": NSApplication.shared.windows.first(where: { $0.title.isEmpty && $0.level.rawValue == 26 })?.windowNumber ?? -1]
                    report["command"] = command; report["app_error"] = model.error as Any? ?? NSNull()
                    report["probe_error"] = probe.receiver?.error as Any? ?? NSNull()
                    try write(report, to: root.appendingPathComponent(id + "-overlay.json"))
                    if let visible = probe.receiver?.snapshot() {
                        try ImageExport.writePNG(visible, to: root.appendingPathComponent(id + "-visible.png"))
                    }
                } else if action == "record" {
                    let oldSplit = model.settings.split
                    model.settings.split = 0.5
                    try await Task.sleep(for: .seconds(1))
                    guard let frame = model.frame else { throw PortError.message("No live frame available") }
                    let recorder = Recording()
                    try await recorder.start(url: root.appendingPathComponent(id + ".mp4"), width: CVPixelBufferGetWidth(frame.pixels), height: CVPixelBufferGetHeight(frame.pixels), withAudio: false)
                    try ImageExport.writePNG(frame.pixels, to: root.appendingPathComponent(id + ".png"))
                    let end = Date().timeIntervalSince1970 + (command["seconds"] as? Double ?? 8)
                    var previous = -1.0
                    while Date().timeIntervalSince1970 < end {
                        if let current = model.frame, current.capturedAt != previous { recorder.append(current); previous = current.capturedAt }
                        try await Task.sleep(for: .milliseconds(2))
                    }
                    try await recorder.stop()
                    model.settings.split = oldSplit
                    try write(["id": id, "recorded": true, "timing": "Original ScreenCaptureKit timestamps retained; real-time recording excluded from performance samples"], to: root.appendingPathComponent("app-ack.json"))
                }
            }
        } catch {
            await model.stop()
            model.error = error.localizedDescription
            controls.makeKeyAndOrderFront(nil)
            try? write(["error": error.localizedDescription], to: root.appendingPathComponent("app-error.json"))
        }
    }
}
