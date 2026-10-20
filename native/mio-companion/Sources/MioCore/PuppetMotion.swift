import Foundation

public struct PuppetMotion: Sendable {
    public var torso: Float = 0
    public var head: Float = 0
    public var headShift = SIMD2<Float>.zero
    public var leftShoulder: Float = 0
    public var rightShoulder: Float = 0
    public var leftElbow: Float = 0
    public var rightElbow: Float = 0
    public var leftWrist: Float = 0
    public var rightWrist: Float = 0

    public init(pose: RigPose) {
        let t = pose.time
        torso = pose.sway * 0.012
        head = pose.lookX * 0.055 + Float(sin(t * 0.72 - 0.5)) * 0.022
        headShift = SIMD2(pose.lookX * 3, -pose.lookY * 3 + Float(sin(t * 1.8 - 0.4)) * 1.2)
        leftShoulder = Float(sin(t * 1.15)) * 0.025
        rightShoulder = Float(sin(t * 1.15 + 0.7)) * 0.025
        leftElbow = 0.06; rightElbow = -0.06
        var gesture = pose.gesture
        var phase = pose.gestureTime
        if gesture == .automatic {
            let cycle = t.truncatingRemainder(dividingBy: 52)
            if pose.speaking { gesture = .talk; phase = t.truncatingRemainder(dividingBy: 5) }
            else if cycle < 5 { gesture = .wave; phase = cycle }
            else if cycle >= 16 && cycle < 21 { gesture = .think; phase = cycle - 16 }
            else if cycle >= 34 && cycle < 41 { gesture = .stretch; phase = cycle - 34 }
            else { gesture = .idle; phase = 0 }
        }
        let blend = Self.envelope(phase, duration: gesture.duration)
        let oscillation = Float(sin(phase * 5.5))
        switch gesture {
        case .wave:
            rightShoulder += 0.65 * sin(.pi * blend) - 0.9 * blend * blend
            rightElbow += (-1.8 + 0.16 * oscillation) * sqrt(blend)
            rightWrist = 0.23 * oscillation * blend
            head += 0.045 * blend; torso -= 0.015 * blend
        case .stretch:
            let liftedShoulder = 2.35 * blend * blend - 0.85 * sin(.pi * blend)
            leftShoulder += liftedShoulder; rightShoulder -= liftedShoulder
            let foldedElbow = 2.5 * sin(.pi * blend) + 0.35 * blend
            leftElbow += foldedElbow; rightElbow -= foldedElbow
            headShift.y -= 3 * blend
            head += Float(sin(phase * 1.2)) * 0.035 * blend
        case .think:
            rightShoulder += 0.5 * blend + 0.35 * sin(.pi * blend); rightElbow -= 2.55 * blend
            rightWrist = -0.12 * blend
            head += 0.075 * blend; torso += 0.012 * blend
        case .talk:
            rightShoulder += (0.20 + 0.04 * oscillation) * blend
            rightElbow -= (0.65 + 0.08 * oscillation) * blend
            leftShoulder -= 0.08 * blend; leftElbow += 0.18 * blend
            headShift.y += Float(sin(phase * 4)) * 1.6 * blend
            head += Float(sin(phase * 2)) * 0.025 * blend
        case .idle, .automatic: break
        }
    }

    public static func smooth(_ low: Float, _ high: Float, _ value: Float) -> Float {
        let x = max(0, min(1, (value - low) / (high - low)))
        return x * x * (3 - 2 * x)
    }
    public func blended(from previous: PuppetMotion, fraction: Float) -> PuppetMotion {
        if fraction <= 0 { return previous }
        if fraction >= 1 { return self }
        let t = fraction
        func mix(_ a: Float, _ b: Float) -> Float { a + (b - a) * t }
        var result = self
        result.torso = mix(previous.torso, torso)
        result.head = mix(previous.head, head)
        result.headShift = previous.headShift + (headShift - previous.headShift) * t
        result.leftShoulder = mix(previous.leftShoulder, leftShoulder)
        result.rightShoulder = mix(previous.rightShoulder, rightShoulder)
        result.leftElbow = mix(previous.leftElbow, leftElbow)
        result.rightElbow = mix(previous.rightElbow, rightElbow)
        result.leftWrist = mix(previous.leftWrist, leftWrist)
        result.rightWrist = mix(previous.rightWrist, rightWrist)
        return result
    }
    public static func envelope(_ time: Double, duration: Double) -> Float {
        smooth(0, 0.85, Float(time)) * (1 - smooth(Float(duration - 0.9), Float(duration), Float(time)))
    }
    public static func rotate(_ point: SIMD2<Float>, around pivot: SIMD2<Float>, by angle: Float) -> SIMD2<Float> {
        let q = point - pivot
        return pivot + SIMD2(q.x * cos(angle) - q.y * sin(angle), q.x * sin(angle) + q.y * cos(angle))
    }
    public func headPoint(_ point: SIMD2<Float>) -> SIMD2<Float> {
        Self.rotate(point, around: SIMD2(300, 305), by: head) + headShift
    }
    public func neckPoint(_ point: SIMD2<Float>) -> SIMD2<Float> {
        let influence = 1 - Self.smooth(272, 310, point.y)
        return point + (headPoint(point) - point) * influence
    }
    public func torsoPoint(_ point: SIMD2<Float>, influence: Float = 1) -> SIMD2<Float> {
        Self.rotate(point, around: SIMD2(300, 520), by: torso * influence)
    }
    public func armPoint(_ point: SIMD2<Float>, shoulder: SIMD2<Float>, elbow: SIMD2<Float>, wrist: SIMD2<Float>, left: Bool) -> SIMD2<Float> {
        let axis = wrist - elbow
        let length = sqrt(axis.x * axis.x + axis.y * axis.y)
        let direction = axis / max(1, length)
        func along(_ origin: SIMD2<Float>) -> Float {
            let delta = point - origin
            return delta.x * direction.x + delta.y * direction.y
        }
        let wristWeight = Self.smooth(-12, 12, along(wrist))
        var p = point + (Self.rotate(point, around: wrist, by: left ? leftWrist : rightWrist) - point) * wristWeight
        let elbowWeight = Self.smooth(-18, 18, along(elbow))
        p += (Self.rotate(p, around: elbow, by: left ? leftElbow : rightElbow) - p) * elbowWeight
        let shoulderWeight = Self.smooth(-8, 20, (point.y - shoulder.y))
        p += (Self.rotate(p, around: shoulder, by: left ? leftShoulder : rightShoulder) - p) * shoulderWeight
        return torsoPoint(p)
    }
}
