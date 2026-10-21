import Foundation

public enum CharacterGesture: String, CaseIterable, Sendable {
    case automatic, idle, wave, think, talk, encourage
    public var title: String {
        switch self {
        case .automatic: return "自动"
        case .idle: return "放下"
        case .wave: return "招手"
        case .think: return "思考"
        case .talk: return "说话"
        case .encourage: return "加油"
        }
    }
    public var duration: Double { 5 }
}

public struct RigPose: Sendable, Equatable {
    public var time: Double
    public var mood: Mood
    public var lookX: Float
    public var lookY: Float
    public var speaking: Bool
    public var gesture: CharacterGesture
    public var gestureTime: Double
    public var cueGesture: CharacterGesture?
    public var cueTime: Double = 0
    public var speech: SpeechTimeline?
    public var speechTime: Double = 0
    public var nod: Float = 0
    public var expression: EmotionalExpression?
    public var resolvedGesture: CharacterGesture { gesture == .automatic ? (cueGesture ?? (speaking ? .talk : .idle)) : gesture }
    public var resolvedTime: Double { gesture == .automatic ? (cueGesture == nil ? gestureTime : cueTime) : gestureTime }
    public init(time: Double, mood: Mood = .neutral, lookX: Float = 0, lookY: Float = 0, speaking: Bool = false, gesture: CharacterGesture = .automatic, gestureTime: Double? = nil) {
        self.time = time; self.mood = mood; self.lookX = max(-1, min(1, lookX)); self.lookY = max(-1, min(1, lookY)); self.speaking = speaking
        self.gesture = gesture; self.gestureTime = gestureTime ?? time
    }
    public var blink: Float {
        return FaceRig.blink(time)
    }
    public var breath: Float { Float(sin(time * 1.8)) }
    public var sway: Float { Float(sin(time * 0.8)) }
    public var mouthOpen: Bool { mouthAmount > 0.15 }
    public var mouthAmount: Float {
        guard speaking else { return 0 }
        return (speech ?? SpeechTimeline("嗯，我在听。慢慢说就好。" )).mouth(at:speech == nil ? gestureTime.truncatingRemainder(dividingBy:5) : speechTime)
    }
}
