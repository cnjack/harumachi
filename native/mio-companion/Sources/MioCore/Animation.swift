import Foundation

public enum CharacterGesture: String, CaseIterable, Sendable {
    case automatic, idle, wave, stretch, think, talk
    public var title: String {
        switch self {
        case .automatic: return "自动"
        case .idle: return "轻摆"
        case .wave: return "招手"
        case .stretch: return "伸懒腰"
        case .think: return "思考"
        case .talk: return "说话"
        }
    }
    public var duration: Double { self == .stretch ? 7 : 5 }
}

public struct RigPose: Sendable, Equatable {
    public var time: Double
    public var mood: Mood
    public var lookX: Float
    public var lookY: Float
    public var speaking: Bool
    public var gesture: CharacterGesture
    public var gestureTime: Double
    public init(time: Double, mood: Mood = .neutral, lookX: Float = 0, lookY: Float = 0, speaking: Bool = false, gesture: CharacterGesture = .automatic, gestureTime: Double? = nil) {
        self.time = time; self.mood = mood; self.lookX = max(-1, min(1, lookX)); self.lookY = max(-1, min(1, lookY)); self.speaking = speaking
        self.gesture = gesture; self.gestureTime = gestureTime ?? time
    }
    public var blink: Float {
        if mood == .sleepy { return 1 }
        let phase = time.truncatingRemainder(dividingBy: 4.7)
        return Float(max(0, 1 - abs(phase - 4.25) / 0.12))
    }
    public var breath: Float { Float(sin(time * 1.8)) }
    public var sway: Float { Float(sin(time * 0.8)) }
    public var mouthOpen: Bool { speaking && sin(time * 15) > -0.15 }
}
