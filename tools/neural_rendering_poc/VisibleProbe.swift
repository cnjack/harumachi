// A bounded display-compositor probe, restricted to the game rectangle and the two test apps.
// Cross-checks whether the game rectangle contains delayed processed frames.
// The floating overlay returned zero presentedTime on the tested macOS/display.
import AppKit
import CoreMedia
import CoreVideo
import ScreenCaptureKit

final class VisibleReceiver: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    var error: String?
    func stream(_ stream: SCStream, didStopWithError error: Error) { self.error = error.localizedDescription }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              attachments.first?[.status] as? Int == SCFrameStatus.complete.rawValue,
              let pixels = sampleBuffer.imageBuffer else { return }
        LiveMetrics.shared.observed(pixels, host: sampleBuffer.presentationTimeStamp.seconds)
        lock.lock(); latest = pixels; lock.unlock()
    }
    func snapshot() -> CVPixelBuffer? { lock.lock(); defer { lock.unlock() }; return latest }
}

@MainActor
final class VisibleProbe {
    private var stream: SCStream?
    private(set) var receiver: VisibleReceiver?
    func start(source: CaptureSource) async throws {
        guard let window = source.window, let gamePID = window.owningApplication?.processID else { throw PortError.message("Window probe requires a game window") }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.max(by: { left, right in
            let a = left.frame.intersection(source.frame), b = right.frame.intersection(source.frame)
            return a.width * a.height < b.width * b.height
        }) else { throw PortError.message("Game display not found") }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let excluded = content.windows.filter { $0.owningApplication?.processID != gamePID && $0.owningApplication?.processID != ownPID }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        print("Visible probe: own apps=\(content.applications.filter { $0.processID == ownPID }.count), own windows=\(content.windows.filter { $0.owningApplication?.processID == ownPID }.count), excluded other windows=\(excluded.count)")
        fflush(stdout)
        let config = SCStreamConfiguration()
        config.sourceRect = source.frame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        config.width = Int(source.frame.width * CGFloat(filter.pointPixelScale))
        config.height = Int(source.frame.height * CGFloat(filter.pointPixelScale))
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = false; config.capturesAudio = false
        let receiver = VisibleReceiver()
        let stream = SCStream(filter: filter, configuration: config, delegate: receiver)
        try stream.addStreamOutput(receiver, type: .screen, sampleHandlerQueue: DispatchQueue(label: "harumachi.visible-probe", qos: .userInitiated))
        self.receiver = receiver; self.stream = stream
        try await stream.startCapture()
    }
    func stop() async { let current = stream; stream = nil; try? await current?.stopCapture(); receiver = nil }
}
