import Foundation

public struct PuppetMotion: Sendable {
    public var torso: Float = 0
    public var torsoLift: Float = 0
    public var head: Float = 0
    public var headShift = SIMD2<Float>.zero
    public var leftShoulder: Float = 0
    public var rightShoulder: Float = 0
    public var leftElbow: Float = 0
    public var rightElbow: Float = 0
    public var leftWrist: Float = 0
    public var rightWrist: Float = 0
    /// Registered source drawings: relaxed, palm out, hand back, inward/side.
    public var leftHand = SIMD4<Float>(1, 0, 0, 0)
    public var rightHand = SIMD4<Float>(1, 0, 0, 0)
    /// Fifth registered drawing; together with the four weights above sums to 1.
    public var leftFist: Float = 0
    public var rightFist: Float = 0
    public var rightChin: Float = 0
    public var thoughtOpacity: Float = 0
    /// Measured index tip after registration of chin-index.png at its wrist.
    public static let thinkingFinger = SIMD2<Float>(547,554)

    public init(pose: RigPose) {
        let t = pose.time
        torso = pose.sway * 0.012
        head = pose.lookX * 0.055 + Float(sin(t * 0.72 - 0.5)) * 0.022
        headShift = SIMD2(pose.lookX * 3, -pose.lookY * 3 + Float(sin(t * 1.8 - 0.4)) * 1.2)
        leftShoulder = Float(sin(t * 1.15)) * 0.018
        rightShoulder = Float(sin(t * 1.15 + 0.7)) * 0.018
        leftElbow = 0.04; rightElbow = -0.04
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
        let rise: Float = gesture == .stretch ? 1.5 : (gesture == .wave ? 1.35 : 0.85)
        let blend = Self.envelope(phase, duration: gesture.duration,rise:rise,fall:gesture == .think ? 0.9 : 1.5)
        let handBlend = Self.smooth(0,0.4,Float(phase))
            * (1-Self.smooth(Float(gesture.duration-0.4),Float(gesture.duration),Float(phase)))
        let presentedPalm = Self.smooth(0.18,0.60,Float(phase))
            * (1-Self.smooth(Float(gesture.duration-1.2),Float(gesture.duration-0.6),Float(phase)))
        let oscillation = Float(sin(phase * 5.5))
        switch gesture {
        case .wave:
            rightHand = SIMD4(1 - presentedPalm, presentedPalm, 0, 0)
            rightShoulder -= 0.65 * Self.smooth(0.25, 1, blend)
            rightElbow -= (1.95 + 0.10 * oscillation) * Self.smooth(0, 0.65, blend)
            rightWrist = 0.13 * oscillation * blend
            head += 0.045 * blend; torso -= 0.035 * blend
        case .stretch:
            // Close before lifting and release after lowering, with the wrist
            // aligned to the forearm throughout the relaxed overhead stretch.
            let grip = Self.smooth(0,0.35,Float(phase))
                * (1-Self.smooth(Float(gesture.duration-0.35),Float(gesture.duration),Float(phase)))
            leftFist = grip; rightFist = grip
            leftHand = SIMD4(1-grip,0,0,0)
            rightHand = leftHand
            // Lift outwards throughout the motion; the previous anticipation
            // reversed the shoulder and folded the elbow almost 180 degrees.
            let liftedShoulder = 1.85 * Self.smooth(0, 1, blend)
            leftShoulder += liftedShoulder; rightShoulder -= liftedShoulder
            let foldedElbow = 1.25 * sin(.pi * blend) + 0.25 * blend
            leftElbow += foldedElbow; rightElbow -= foldedElbow
            headShift.y -= 3 * blend
            torsoLift = 5 * blend
            torso += Float(sin(phase * 0.9)) * 0.025 * blend
            head += Float(sin(phase * 1.2)) * 0.035 * blend
        case .think:
            rightChin = handBlend
            rightHand = SIMD4(1-handBlend,0,0,0)
            head += 0.13 * blend; torso += 0.018 * blend
            // Solve the two painted sleeve pieces against the actual index
            // tip, keeping contact as the head tilts and follows the pointer.
            let shoulder = SIMD2<Float>(369,320), elbow = SIMD2<Float>(427,418)
            let target = headPoint(SIMD2(300,268))+SIMD2(1,1)
            let axis = SIMD2<Float>(59,90)
            let direction = axis/sqrt(axis.x*axis.x+axis.y*axis.y)
            let reach = target-shoulder
            let distance = sqrt(reach.x*reach.x+reach.y*reach.y)
            var low: Float = 2.5, high: Float = 4.15
            for _ in 0..<22 {
                let angle = (low+high)/2
                let p = Self.bend(Self.thinkingFinger,at:elbow,direction:direction,angle:angle,span:116)-shoulder
                if sqrt(p.x*p.x+p.y*p.y) > distance { low = angle } else { high = angle }
            }
            let angle = (low+high)/2
            let bent = Self.bend(Self.thinkingFinger,at:elbow,direction:direction,angle:angle,span:116)-shoulder
            let rawShoulder = atan2(reach.y,reach.x)-atan2(bent.y,bent.x)
            let solvedShoulder = atan2(sin(rawShoulder),cos(rawShoulder))
            rightShoulder += (solvedShoulder-rightShoulder)*blend
            rightElbow += (angle-rightElbow)*blend
            thoughtOpacity = Self.smooth(0.85,1.2,Float(phase))
                * (1-Self.smooth(3.9,4.2,Float(phase)))
        case .talk:
            rightHand = SIMD4(1 - presentedPalm, presentedPalm, 0, 0)
            rightShoulder += (0.10 + 0.03 * oscillation) * blend
            rightElbow -= (0.55 + 0.06 * oscillation) * blend
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
        result.torsoLift = mix(previous.torsoLift,torsoLift)
        result.head = mix(previous.head, head)
        result.headShift = previous.headShift + (headShift - previous.headShift) * t
        result.leftShoulder = mix(previous.leftShoulder, leftShoulder)
        result.rightShoulder = mix(previous.rightShoulder, rightShoulder)
        result.leftElbow = mix(previous.leftElbow, leftElbow)
        result.rightElbow = mix(previous.rightElbow, rightElbow)
        result.leftWrist = mix(previous.leftWrist, leftWrist)
        result.rightWrist = mix(previous.rightWrist, rightWrist)
        result.leftHand = previous.leftHand + (leftHand - previous.leftHand) * t
        result.rightHand = previous.rightHand + (rightHand - previous.rightHand) * t
        result.leftFist = mix(previous.leftFist,leftFist)
        result.rightFist = mix(previous.rightFist,rightFist)
        result.rightChin = mix(previous.rightChin,rightChin)
        result.thoughtOpacity = mix(previous.thoughtOpacity,thoughtOpacity)
        return result
    }
    public static func envelope(_ time: Double, duration: Double, rise: Float = 0.85, fall: Double = 0.9) -> Float {
        smooth(0, rise, Float(time)) * (1 - smooth(Float(duration - fall), Float(duration), Float(time)))
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
        var p = point
        p.y -= torsoLift*(1-Self.smooth(310,650,p.y))*influence
        return Self.rotate(p, around: SIMD2(300, 432), by: torso * influence)
    }
    public func lowerBodyPoint(_ point: SIMD2<Float>) -> SIMD2<Float> {
        // The hidden waist extension follows the blouse; the hem and legs stay
        // planted. Artwork overlap carries the joint through the full bend.
        torsoPoint(point, influence: 1 - Self.smooth(432, 690, point.y))
    }
    /// Bend a strip through a circular arc, preserving its transverse width.
    /// Blending rotated positions collapses the inside of a bent sleeve and can
    /// reverse triangles. Here the centreline has unit arc length and the radius
    /// stays larger than the sleeve half-width, as checked against opaque pixels.
    private static func bend(_ point: SIMD2<Float>, at origin: SIMD2<Float>,
                             direction: SIMD2<Float>, angle: Float, span: Float) -> SIMD2<Float> {
        guard abs(angle) > 0.0001 else { return point }
        let normal = SIMD2(-direction.y, direction.x)
        let delta = point - origin
        let along = delta.x * direction.x + delta.y * direction.y
        let across = delta.x * normal.x + delta.y * normal.y
        let half = span / 2
        guard along > -half else { return point }
        let distance = min(span, along + half)
        let turn = angle * distance / span
        let radius = span / angle
        let tangent = direction * cos(turn) + normal * sin(turn)
        let side = normal * cos(turn) - direction * sin(turn)
        let center = origin - direction * half
            + direction * (sin(turn) * radius) + normal * ((1 - cos(turn)) * radius)
            + tangent * max(0, along - half)
        return center + side * across
    }
    public func armPoint(_ point: SIMD2<Float>, shoulder: SIMD2<Float>, elbow: SIMD2<Float>, wrist: SIMD2<Float>, left: Bool,
                         elbowBendSpan: Float = 116, wristBendSpan: Float = 30, upperArm: Bool? = nil) -> SIMD2<Float> {
        let axis = wrist - elbow
        let direction = axis / max(1, sqrt(axis.x * axis.x + axis.y * axis.y))
        var p = Self.bend(point, at: wrist, direction: direction,
                          angle: left ? leftWrist : rightWrist, span: wristBendSpan)
        p = Self.bend(p,at:elbow,direction:direction,angle:left ? leftElbow : rightElbow,span:elbowBendSpan)
        // The whole shoulder cap belongs to the upper arm. A Y mask here pins
        // half the cap to the torso and twists it when the arm is raised.
        p = Self.rotate(p, around: shoulder, by: left ? leftShoulder : rightShoulder)
        return torsoPoint(p)
    }
}
