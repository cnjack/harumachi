import Foundation

extension RigPose {
    /// Select the performance channels owned by the current user mode.
    public mutating func present(_ cue: PerformanceCue?,elapsed: Double,expressionOverride: ExpressionStyle? = nil) {
        if let cue { cue.apply(to:&self,elapsed:elapsed) }
        else { cueGesture=nil;speech=nil;nod=0;expression=nil }
        if gesture != .automatic {
            // A manual gesture owns the arms, not the face or the new reply's
            // punctuation. The cue can therefore update and release its face.
            cueGesture=nil;nod=0
            if gesture == .talk && gestureTime < gesture.duration && !speaking {
                speaking=true;speech=nil;speechTime=0
            }
        }
        if let style = expressionOverride {
            // Manual face selection owns eyebrows/eyes/lip shape only. Keep the
            // latest decision's hand and speech channels, including punctuation.
            expression = EmotionalExpression(style:style,hand:expression?.hand ?? .rest)
            mood = style.mood
        }
    }
}

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
    public let expression: EmotionalExpression?
    public let speech: SpeechTimeline
    public init(intent: Intent,mood: Mood,text: String = "",at date: Date = Date(),expression: EmotionalExpression? = nil) {
        id = UUID();started = date;self.intent = intent;self.mood = mood
        self.text = text;speech = SpeechTimeline(text);self.expression=expression
    }
    public func apply(to pose: inout RigPose,elapsed: Double) {
        pose.mood = expression?.style.mood ?? mood
        pose.expression = expression
        pose.cueGesture = .idle;pose.cueTime = max(0,elapsed)
        pose.speechTime = elapsed-(intent == .welcome ? 0.35:0)
        let speechActive = !text.isEmpty && intent != .waiting && intent != .quiet
            && pose.speechTime >= 0 && pose.speechTime < speech.duration
        pose.speech = speechActive ? speech:nil
        pose.speaking = speechActive
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
        // Model-selected hands describe the reply, including short answers. Quiet
        // events never move hands; the greeting director still owns cooldown.
        if let expression,intent == .reply,elapsed < max(3.6,speech.duration) {
            switch expression.hand {
            case .rest: pose.cueGesture = .idle
            case .wave: pose.cueGesture = .wave;pose.cueTime=min(5,elapsed)
            case .explain: pose.cueGesture = .talk;pose.cueTime=min(3.8,elapsed)
            case .encourage: pose.cueGesture = .encourage;pose.cueTime=min(3.8,elapsed)
            case .chin: pose.cueGesture = .think;pose.cueTime=min(2.2,elapsed)
            }
        }
        if elapsed > max(3.6,speech.duration)+2, intent != .waiting {
            pose.mood = .neutral;pose.expression=EmotionalExpression(style:.neutral)
        }
    }
}

/// Clef chooses intent and expression; this director owns timing and frequency.
public struct PerformanceDirector {
    private var lastWelcome = Date.distantPast
    public init() {}
    public mutating func response(_ decision: Decision,event: SystemEvent,text: String,now: Date) -> PerformanceCue {
        if decision.reaction == .none || decision.reaction == .focus {
            return PerformanceCue(intent:.quiet,mood:decision.mood,text:text,at:now,expression:decision.expression)
        }
        let greeting = decision.reaction == .greet && ["startup","wake","session.active","message"].contains(event.kind)
        if greeting && now.timeIntervalSince(lastWelcome) >= 180 {
            lastWelcome = now
            return PerformanceCue(intent:.welcome,mood:decision.mood,text:text,at:now,expression:decision.expression)
        }
        var expression=decision.expression
        if let e=expression,e.hand == .wave {
            if now.timeIntervalSince(lastWelcome)<180 { expression=EmotionalExpression(style:e.style,intensity:e.intensity,hand:.rest) }
            else { lastWelcome=now }
        }
        return PerformanceCue(intent:.reply,mood:decision.mood,text:text,at:now,expression:expression)
    }
}
