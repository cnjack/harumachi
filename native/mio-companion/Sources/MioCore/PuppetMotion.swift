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
        let attention = FaceRig.attention(t-0.12)
        headShift = SIMD2((pose.lookX+attention.x)*3, -(pose.lookY+attention.y)*3 + Float(sin(t * 1.8 - 0.4)) * 1.2)
        leftShoulder = Float(sin(t * 1.15)) * 0.018
        rightShoulder = Float(sin(t * 1.15 + 0.7)) * 0.018
        leftElbow = 0.04; rightElbow = -0.04
        let gesture = pose.resolvedGesture
        let phase = pose.resolvedTime
        headShift.y += pose.nod*1.4
        torso += pose.nod*0.007
        let rise: Float = gesture == .wave ? 0.55 : 0.48
        let blend = Self.envelope(phase, duration: gesture.duration,rise:rise,fall:0.6)
        // The source artwork spreads its arms for rigging. The authored rest
        // pose closes the shoulders so both wrists hang beside the hips.
        // Release only the arm used by the gesture, preserving held targets.
        let rightActivity = gesture == .idle || gesture == .automatic ? 0 : blend
        leftShoulder -= 0.38
        rightShoulder += 0.38 * (1-rightActivity)
        let handBlend = Self.smooth(0,0.22,Float(phase))
            * (1-Self.smooth(Float(gesture.duration-0.4),Float(gesture.duration),Float(phase)))
        let presentedPalm = Self.smooth(0.08,0.28,Float(phase))
            * (1-Self.smooth(Float(gesture.duration-0.45),Float(gesture.duration-0.15),Float(phase)))
        let waveBeats: [(Float,Float)] = [(0,0),(0.65,0),(0.90,0.85),(1.22,-0.9),(1.56,1),
            (1.93,-0.75),(2.29,0.8),(2.65,-0.65),(3.02,0.55),(3.42,-0.3),(3.8,0),(5,0)]
        let oscillation = Self.phrase(Float(phase),keys:waveBeats)
        let anticipation = Self.smooth(0,0.12,Float(phase))*(1-Self.smooth(0.12,0.32,Float(phase)))
        if gesture != .idle { torso += 0.012*anticipation;head -= 0.018*anticipation }
        switch gesture {
        case .wave:
            rightHand = SIMD4(1 - presentedPalm, presentedPalm, 0, 0)
            // Elbow leads, wrist follows, with a small shoulder/body response.
            // Their different phases keep the greeting from moving as one rod.
            rightShoulder += (-0.65 * Self.smooth(0.25,1,blend)
                + 0.035 * Self.phrase(Float(phase-0.12),keys:waveBeats)*blend)
            rightElbow -= (1.95 + 0.185 * oscillation) * Self.smooth(0, 0.65, blend)
            rightWrist = 0.19 * Self.phrase(Float(phase-0.08),keys:waveBeats) * blend
            head += (0.045+0.026*Float(sin(phase*4.3-0.7))) * blend
            torso += (-0.032+0.006*Float(sin(phase*4.3-1))) * blend
        case .think:
            rightChin = handBlend
            rightHand = SIMD4(1-handBlend,0,0,0)
            head += 0.13 * blend; torso += 0.018 * blend
            // Solve the two painted sleeve pieces against the actual index
            // tip, keeping contact as the head tilts and follows the pointer.
            let shoulder = SIMD2<Float>(369,320), elbow = SIMD2<Float>(427,418)
            let target = headPoint(SIMD2(300,268))+SIMD2(1,1)
            let upper = elbow-shoulder,lower = Self.thinkingFinger-elbow
            let l1 = sqrt(upper.x*upper.x+upper.y*upper.y),l2 = sqrt(lower.x*lower.x+lower.y*lower.y)
            let offset = atan2(lower.y,lower.x)-atan2(upper.y,upper.x)
            var solvedShoulder = rightShoulder,angle = rightElbow
            // Solve against the placed shoulder, including its small garment
            // lift. Re-evaluate because placement depends on shoulder angle.
            for _ in 0..<48 {
                let placed = shoulder+SIMD2(-Self.shoulderInset(-solvedShoulder),-Self.shoulderLift(-solvedShoulder))
                let reach = target-placed
                let cosine = max(-1,min(1,(reach.x*reach.x+reach.y*reach.y-l1*l1-l2*l2)/(2*l1*l2)))
                angle = acos(cosine)-offset
                let bent = upper+Self.rotate(lower,around:.zero,by:angle)
                let rawShoulder = atan2(reach.y,reach.x)-atan2(bent.y,bent.x)
                let correction = atan2(sin(rawShoulder-solvedShoulder),cos(rawShoulder-solvedShoulder))
                solvedShoulder += correction*0.25
            }
            rightShoulder += (solvedShoulder-rightShoulder)*blend
            rightElbow += (angle-rightElbow)*blend
            thoughtOpacity = Self.smooth(0.55,0.8,Float(phase))
                * (1-Self.smooth(3.9,4.2,Float(phase)))
        case .talk:
            rightHand = SIMD4(1 - presentedPalm, presentedPalm, 0, 0)
            let speechBeats: [(Float,Float)] = [(0,0),(0.7,0.2),(1.15,0.9),(1.7,-0.45),
                (2.3,-0.45),(2.85,0.6),(3.45,-0.2),(4.1,0.35),(5,0)]
            let beat = Self.phrase(Float(phase),keys:speechBeats)
            rightShoulder += (0.10 + 0.085 * Self.phrase(Float(phase-0.1),keys:speechBeats)) * blend
            rightElbow -= (0.55 + 0.23 * beat) * blend
            rightWrist = 0.12*Self.phrase(Float(phase-0.17),keys:speechBeats)*blend
            leftShoulder -= (0.08+0.025*Float(sin(phase*3.8-0.7))) * blend
            leftElbow += (0.18+0.05*Float(sin(phase*3.8))) * blend
            let emphasis = (pose.speech ?? SpeechTimeline("嗯，我在听。慢慢说就好。")).emphasis(at:pose.speech == nil ? phase : pose.speechTime)
            headShift.y += emphasis * 1.2 * blend
            head += Float(sin(phase * 2.9)) * 0.035 * blend
            torso += Float(sin(phase * 2.9-0.8))*0.012*blend
        case .encourage:
            rightFist=handBlend;rightHand=SIMD4(1-handBlend,0,0,0)
            // One small reassuring fist near the shoulder. No punch or thrust.
            let beat=Self.phrase(Float(phase),keys:[(0,0),(0.8,0),(1.1,0.8),(1.5,0),(2.2,0.45),(2.6,0),(5,0)])
            rightShoulder += (0.50+0.025*beat)*blend
            rightElbow += (-2.66-0.06*beat)*blend
            rightWrist = -0.05*blend
            torso -= 0.016*blend;head += 0.03*blend;headShift.y += beat*0.7
        case .idle, .automatic: break
        }
    }

    public static func smooth(_ low: Float, _ high: Float, _ value: Float) -> Float {
        let x = max(0, min(1, (value - low) / (high - low)))
        return x * x * (3 - 2 * x)
    }
    public static func phrase(_ time: Float,keys: [(Float,Float)]) -> Float {
        for index in 1..<keys.count where time < keys[index].0 {
            let (a,x) = keys[index-1],(b,y) = keys[index]
            return x+(y-x)*smooth(a,b,time)
        }
        return keys.last?.1 ?? 0
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
        Self.rotate(FaceRig.turn(point,x:headShift.x*10,y:-headShift.y*4), around: SIMD2(300, 305), by: head) + headShift
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
    /// Two rigid bone segments meet at the painted elbow overlap. The hand
    /// turns about the wrist independently. Source pieces own their hidden
    /// overlap; no long strip is stretched into a sleeve-shaped spline.
    public func armPoint(_ point: SIMD2<Float>, shoulder: SIMD2<Float>, elbow: SIMD2<Float>, wrist: SIMD2<Float>, left: Bool,
                         elbowBendSpan: Float = 116, wristBendSpan: Float = 30, upperArm: Bool? = nil,
                         hand: Bool = false) -> SIMD2<Float> {
        let axis = wrist-elbow,direction = axis/max(1,sqrt(axis.x*axis.x+axis.y*axis.y))
        let delta = point-elbow,lower = upperArm.map { !$0 } ?? (delta.x*direction.x+delta.y*direction.y >= -0.001)
        let shoulderAngle = left ? leftShoulder:rightShoulder
        var p = upperArm == true ? Self.sleeveRoot(point,shoulder:shoulder,elbow:elbow,
            lift:left ? shoulderAngle:-shoulderAngle) : point
        if lower {
            let dw = p-wrist
            if hand || (upperArm == nil && dw.x*direction.x+dw.y*direction.y > 0) {
                p = Self.rotate(p,around:wrist,by:left ? leftWrist:rightWrist)
            }
            p = Self.rotate(p,around:elbow,by:left ? leftElbow:rightElbow)
        }
        p = Self.rotate(p,around:shoulder,by:left ? leftShoulder:rightShoulder)
        let outward = left ? shoulderAngle:-shoulderAngle
        let lift = Self.shoulderLift(outward)
        let inset = Self.shoulderInset(outward)*(left ? 1:-1)
        return Self.rotate(p+SIMD2(inset,-torsoLift-lift),around:SIMD2(300,432),by:torso)
    }
    public static func shoulderLift(_ outwardAngle: Float) -> Float {
        // Raise the resting sleeve to the garment shoulder, preserving the
        // approved wave. Match interpolation between exported parent keyforms
        // so the fingertip solver and standalone MOC playback share a pivot.
        func key(_ angle: Float) -> Float {
            let resting = smooth(-0.65,-0.48,angle)*(1-smooth(-0.3,-0.08,angle))
            return 7*resting+20*smooth(0.9,1.55,angle)
        }
        let low = floor(outwardAngle*10)/10,fraction = (outwardAngle-low)*10
        return key(low)+(key(low+0.1)-key(low))*fraction
    }
    public static func shoulderInset(_ outwardAngle: Float) -> Float { 12*smooth(0.9,1.55,outwardAngle) }
    /// Tuck only the painted overlap behind the armhole as the arm rises.
    /// The visible upper arm and all bone anchors retain their rigid shape.
    /// These same points are authored as Cubism shoulder keyforms by the baker.
    public static func sleeveRoot(_ p: SIMD2<Float>,shoulder: SIMD2<Float>,elbow: SIMD2<Float>,lift: Float) -> SIMD2<Float> {
        let axis=elbow-shoulder,direction=axis/sqrt(axis.x*axis.x+axis.y*axis.y)
        let normal=SIMD2(-direction.y,direction.x),delta=p-shoulder
        let along=delta.x*direction.x+delta.y*direction.y,across=delta.x*normal.x+delta.y*normal.y
        let raised=smooth(0.9,1.55,lift)
        let longitudinal=1-0.5*raised*(1-smooth(12,42,along))
        let transverse=1-0.5*raised*(1-smooth(12,45,along))
        return shoulder+direction*(along*longitudinal)+normal*(across*transverse)
    }
}
