// Offline AVAudioEngine only: no microphone, speaker, or VoiceProcessing IO.
// Measures buffer continuity, never acoustic interruption latency or AEC.
import AVFoundation
import Foundation

enum ProbeError: Error { case allocation, render(Int) }
let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
let frames = 24000
func pcm(_ values: [Float]) throws -> AVAudioPCMBuffer {
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(values.count)) else { throw ProbeError.allocation }
    buffer.frameLength = AVAudioFrameCount(values.count)
    for (index, value) in values.enumerated() { buffer.floatChannelData![0][index] = value }
    return buffer
}
func run(pauseAt: Int?, cancel: Bool = false, replacement: Bool = true) throws -> [String: Any] {
    let engine = AVAudioEngine(), player = AVAudioPlayerNode()
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: format)
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 480)
    let original = (0..<frames).map { Float(0.1 + 0.05 * sin(Double($0) * 0.031)) }
    // Many queued buffers, mirroring streamed PCM.
    for start in stride(from: 0, to: frames, by: 1920) {
        player.scheduleBuffer(try pcm(Array(original[start..<min(frames, start + 1920)])))
    }
    try engine.start(); player.play()
    defer { player.stop(); engine.stop() }
    func render(_ count: Int) throws -> [Float] {
        var output: [Float] = []
        while output.count < count {
            let n = min(480, count - output.count)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)) else { throw ProbeError.allocation }
            let result = try engine.renderOffline(AVAudioFrameCount(n), to: buffer)
            guard result == .success, buffer.frameLength == AVAudioFrameCount(n) else { throw ProbeError.render(result.rawValue) }
            output.append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        }
        return output
    }
    func cursor() -> Int64 {
        guard let time = player.lastRenderTime, let local = player.playerTime(forNodeTime: time) else { return -1 }
        return local.sampleTime
    }
    let before = try render(pauseAt ?? frames)
    guard let pauseAt else { return ["samples": before] }
    let beforeCursor = cursor()
    if cancel { player.stop() } else { player.pause() }
    let silent = try render(24000)
    let pausedCursor = cursor()
    if cancel && replacement { player.scheduleBuffer(try pcm(Array(repeating: -0.2, count: 6000))) }
    player.play()
    let resumed = try render(cancel && replacement ? 6000 : frames - pauseAt)
    return ["pause_at_frames": pauseAt, "cancel": cancel, "replacement": cancel && replacement,
            "before_cursor": beforeCursor, "paused_cursor": pausedCursor, "resumed_cursor": cursor(),
            "paused_peak": silent.map { abs($0) }.max()!,
            "before": before, "resumed": resumed]
}
let reference = try run(pauseAt: nil)["samples"] as! [Float]
var rows: [[String: Any]] = []
var failures: [String] = []
for point in [480, 4800, 12000, 22080] {
    for (cancel, replacement) in [(false, false), (true, false), (true, true)] {
        var result = try run(pauseAt: point, cancel: cancel, replacement: replacement)
        let before = result.removeValue(forKey: "before") as! [Float]
        let after = result.removeValue(forKey: "resumed") as! [Float]
        if !replacement {
            let reconstructed = before + after
            let error = zip(reconstructed, reference).map { abs($0 - $1) }.max()!
            result["max_error_against_unpaused"] = error
            if !cancel && error > 0.000001 { failures.append("pause/resume lost or duplicated samples at \(point)") }
            // Negative control: the old stop-then-play sequence must fail the
            // continuity test; otherwise this probe cannot detect that bug.
            if cancel && error < 0.01 { failures.append("stop negative control was not detected at \(point)") }
        } else {
            // Old positive samples must not leak into the negative replacement.
            let leaked = after.filter { $0 > 0.001 }.count
            let replacementError = after.map { abs($0 + 0.2) }.max()!
            result["replacement_positive_samples"] = leaked
            result["replacement_max_error"] = replacementError
            if leaked != 0 { failures.append("old response leaked into replacement at \(point)") }
            if replacementError > 0.000001 { failures.append("new response lost or corrupted at \(point)") }
        }
        if (result["paused_peak"] as! Float) > 0.000001 { failures.append("offline pause not silent at \(point)") }
        rows.append(result)
    }
}
let value: [String: Any] = ["method": "Silent offline manual rendering; no audio device or AEC; pause/resume continuity vs stop negative control and stop/replacement", "sample_rate": 24000, "passed": failures.isEmpty, "failures": failures, "rows": rows]
let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(data)
if !failures.isEmpty { exit(1) }
