import Foundation

public struct RigPose: Sendable {
    public var time: Double
    public var mood: Mood
    public var lookX: Float
    public var lookY: Float
    public var speaking: Bool
    public init(time: Double, mood: Mood = .neutral, lookX: Float = 0, lookY: Float = 0, speaking: Bool = false) {
        self.time = time; self.mood = mood; self.lookX = max(-1, min(1, lookX)); self.lookY = max(-1, min(1, lookY)); self.speaking = speaking
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
