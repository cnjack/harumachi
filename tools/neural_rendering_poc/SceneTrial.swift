// Diagnostic adapter for gtrg55/dlss5-macos-overlay. Uses its RenderEngine unchanged.
import Foundation
import CoreImage
import CoreVideo
import ImageIO
import ScreenCore

enum SceneTrial {
    @MainActor static func run() async throws {
        guard let sourcePath = Diagnostics.argument("--scene-trial"),
              let outputPath = Diagnostics.argument("--output") else {
            throw PortError.message("--scene-trial INPUT and --output DIRECTORY are required")
        }
        let source = URL(fileURLWithPath: sourcePath)
        let output = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let isDirectory = (try source.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true
        let files = isDirectory ? try FileManager.default.contentsOfDirectory(at: source,
            includingPropertiesForKeys: nil).filter { $0.pathExtension.lowercased() == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } : [source]
        guard !files.isEmpty, source.standardizedFileURL != output.standardizedFileURL else {
            throw PortError.message("No PNG inputs, or output would overwrite the input")
        }
        let count = isDirectory ? files.count : max(9, Int(Diagnostics.argument("--frames") ?? "18") ?? 18)
        let warmup = min(count - 3, max(1, Int(Diagnostics.argument("--warmup") ?? "6") ?? 6))
        var settings = RenderSettings()
        settings.processingLongEdge = Int(Diagnostics.argument("--width") ?? "512") ?? 512
        settings.profile = Diagnostics.argument("--profile") ?? "natural"
        settings.intensity = Float(Diagnostics.argument("--intensity") ?? "1") ?? 1
        settings.sanitize()
        let surfaces = try MetalFrames()
        let context = CIContext(options: [.cacheIntermediates: false])
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let engine = try RenderEngine()
        try await engine.loadModel(Diagnostics.modelURL())
        var rows = [[String: Any]]()
        var timings = [Double]()
        var sourceSize = FrameSize(0, 0)
        var workSize = FrameSize(0, 0)
        let started = ProcessInfo.processInfo.systemUptime
        for index in 0..<count {
            let file = files[isDirectory ? index : 0]
            guard let imageSource = CGImageSourceCreateWithURL(file as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw PortError.message("Could not decode \(file.path)")
            }
            sourceSize = FrameSize(image.width, image.height)
            let pixels = try surfaces.allocate(sourceSize)
            context.render(CIImage(cgImage: image), to: pixels,
                bounds: CGRect(x: 0, y: 0, width: image.width, height: image.height), colorSpace: colorSpace)
            if index == 0 { try ImageExport.writePNG(pixels, to: output.appendingPathComponent("input-roundtrip.png")) }
            // Presentation timestamps, not wall time: this is an offline sequence.
            let result = try await engine.process(CapturedFrame(pixels: pixels,
                capturedAt: 1000 + Double(index) / 30), settings: settings)
            guard result.neural else { throw PortError.message("Neural inference was bypassed") }
            workSize = result.processingSize
            if index >= warmup { timings.append(result.milliseconds) }
            rows.append(["frame": index, "source": file.lastPathComponent, "milliseconds": result.milliseconds])
            if isDirectory || index == count - 1 {
                let name = isDirectory ? String(format: "%05d.png", index) : "processed.png"
                try ImageExport.writePNG(result.pixels, to: output.appendingPathComponent(name))
            }
            if index % 15 == 0 { print("frame \(index)/\(count): \(result.milliseconds) ms"); fflush(stdout) }
        }
        let ordered = timings.sorted()
        let average = timings.reduce(0, +) / Double(timings.count)
        let report: [String: Any] = ["source": source.path, "gpu": surfaces.device.name,
            "sourceSize": [sourceSize.width, sourceSize.height], "processingSize": [workSize.width, workSize.height],
            "profile": settings.profile, "intensity": settings.intensity, "tone": settings.tone,
            "structure": settings.structure, "temporal": settings.temporal, "frames": count, "warmupFrames": warmup,
            "averageMilliseconds": average, "medianMilliseconds": ordered[ordered.count / 2],
            "p95Milliseconds": ordered[min(ordered.count - 1, Int(ceil(Double(ordered.count) * 0.95)) - 1)],
            "processingFPS": 1000 / average, "wallSeconds": ProcessInfo.processInfo.systemUptime - started,
            "samples": rows,
            "scope": "Offline PNG input through unchanged upstream RenderEngine. Timings include resize, estimated optical flow, neural inference and composition; exclude PNG IO, live capture, game rendering and display. Not game FPS or a native NVIDIA parity claim."]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("metrics.json"))
        print("DONE \(settings.profile) \(workSize.width)x\(workSize.height): \(1000 / average) processing FPS")
    }
}
