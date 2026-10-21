import Foundation

/// A bounded text performance. Whitespace and punctuation are real closed-mouth
/// intervals; no audio is generated or recorded.
public struct SpeechTimeline: Sendable, Equatable {
    public struct Beat: Sendable, Equatable { public let start, end: Double; public let strength: Float }
    public let beats: [Beat]
    public let duration: Double
    public init(_ text: String) {
        var cursor = 0.18, result: [Beat] = []
        for (index,c) in text.prefix(300).enumerated() {
            let mark = String(c)
            if "，、,:：；;".contains(c) { cursor += 0.27;continue }
            if "。！？.!?…\n".contains(c) { cursor += 0.48;continue }
            if mark.trimmingCharacters(in:.whitespaces).isEmpty { cursor += 0.06;continue }
            let length = 0.115+Double(index%4)*0.012
            result.append(Beat(start:cursor,end:cursor+length,strength:0.42+Float(index%3)*0.12))
            cursor += length+0.035
        }
        beats = result;duration = cursor+0.25
    }
    public func mouth(at time: Double) -> Float {
        guard let beat = beats.first(where: { time >= $0.start && time <= $0.end }) else { return 0 }
        let t = Float((time-beat.start)/(beat.end-beat.start))
        return beat.strength*PuppetMotion.smooth(0,0.25,t)*(1-PuppetMotion.smooth(0.6,1,t))
    }
    public func emphasis(at time: Double) -> Float {
        guard let beat = beats.enumerated().first(where: { $0.offset%7 == 0 && time >= $0.element.start && time < $0.element.start+0.48 })?.element else { return 0 }
        let t = Float(time-beat.start)
        return PuppetMotion.smooth(0,0.12,t)*(1-PuppetMotion.smooth(0.2,0.48,t))
    }
}

public struct PerformanceCue: Sendable, Equatable {
    public enum Intent: String, Codable, Sendable { case welcome, waiting, reply, quiet }
    public let id: UUID
    public let started: Date
    public let intent: Intent
    public let mood: Mood
    public let text: String
    public let speech: SpeechTimeline
    public init(intent: Intent,mood: Mood,text: String = "",at date: Date = Date()) {
        id = UUID();started = date;self.intent = intent;self.mood = mood
        self.text = text;speech = SpeechTimeline(text)
    }
    public func apply(to pose: inout RigPose,elapsed: Double) {
        pose.mood = mood
        pose.cueGesture = .idle;pose.cueTime = max(0,elapsed)
        pose.speech = speech;pose.speechTime = elapsed-(intent == .welcome ? 0.35:0)
        pose.speaking = !text.isEmpty && pose.speechTime >= 0 && pose.speechTime < speech.duration
        pose.nod = 0
        switch intent {
        case .welcome:
            if elapsed < 4.4 { pose.cueGesture = .wave;pose.cueTime = elapsed*5/4.4 }
        case .waiting:
            pose.speaking = false
            if elapsed > 0.55 { pose.cueGesture = .think;pose.cueTime = min(2.2,elapsed-0.55) }
        case .reply:
            if pose.speaking && text.count > 16 {
                pose.cueGesture = .talk
                pose.cueTime = min(3.8,max(0,elapsed))
            }
            pose.nod = speech.emphasis(at:pose.speechTime)*0.7
        case .quiet: pose.speaking = false
        }
        if elapsed > speech.duration+2, intent != .waiting { pose.mood = .neutral }
    }
}

/// Clef chooses intent and expression; this director owns timing and frequency.
public struct PerformanceDirector {
    private var lastWelcome = Date.distantPast
    public init() {}
    public mutating func response(_ decision: Decision,event: SystemEvent,text: String,now: Date) -> PerformanceCue {
        if decision.reaction == .none || decision.reaction == .focus {
            return PerformanceCue(intent:.quiet,mood:decision.mood,text:text,at:now)
        }
        let greeting = decision.reaction == .greet && ["startup","wake","session.active","message"].contains(event.kind)
        if greeting && now.timeIntervalSince(lastWelcome) >= 180 {
            lastWelcome = now
            return PerformanceCue(intent:.welcome,mood:decision.mood,text:text,at:now)
        }
        return PerformanceCue(intent:.reply,mood:decision.mood,text:text,at:now)
    }
}
