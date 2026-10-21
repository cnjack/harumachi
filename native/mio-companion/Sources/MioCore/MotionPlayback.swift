import Foundation

/// One motion history for explicit gestures and automatic/speech interruptions.
/// Repeated samples of the same pose are idempotent, including offline snapshots.
public struct MotionPlayback {
    /// Source canvas pixels per second; 60 Hz display keeps a fast gesture smooth.
    public static let maximumHandSpeed: Float = 850
    private var lastPose: RigPose?
    private var lastMotion: PuppetMotion?
    private var effective: CharacterGesture?
    private var previous: PuppetMotion?
    private var start: Double = 0
    private var duration: Double = 0
    private var via: PuppetMotion?
    private var firstDuration: Double = 0
    private var manualStart: Double?
    private var pending = false
    public init() {}
    public mutating func select(_ gesture: CharacterGesture, pose: RigPose) -> Bool {
        _ = sample(pose)
        if gesture == pose.gesture, gesture != .automatic,
           gesture == .idle || pose.gestureTime < gesture.duration - 1.4 { return false }
        manualStart = gesture == .automatic ? nil : pose.time
        pending = true
        lastPose = nil
        return true
    }
    public mutating func sample(_ pose: RigPose) -> PuppetMotion {
        if pose == lastPose, let lastMotion { return lastMotion }
        if let lastPose, pose.time < lastPose.time { self = MotionPlayback() }
        var targetPose = pose
        var resolved = pose.gesture
        if pose.gesture == .automatic {
            let cycle = pose.time.truncatingRemainder(dividingBy: 52)
            if pose.speaking {
                resolved = .talk
                targetPose.gestureTime = 1.25 + max(0, pose.time - start - duration)
            } else if cycle < 5 { resolved = .wave; targetPose.gestureTime = cycle }
            else if cycle >= 16 && cycle < 21 { resolved = .think; targetPose.gestureTime = cycle - 16 }
            else { resolved = .idle; targetPose.gestureTime = 0 }
        } else if manualStart != nil {
            targetPose.gestureTime = pending ? 1.25 : 1.25 + max(0, pose.time - start - duration)
        }
        targetPose.gesture = resolved
        if pose.gesture == .automatic, pose.speaking, resolved != effective { targetPose.gestureTime = 1.25 }
        let target = PuppetMotion(pose: targetPose)
        if (pending || resolved != effective), let lastMotion {
            previous = lastMotion
            start = pose.time
            let oppositeFold = (lastMotion.rightElbow > 0.6 && target.rightElbow < -0.15)
                || (lastMotion.rightElbow < -0.15 && target.rightElbow > 0.6)
            if oppositeFold {
                var neutralPose = pose;neutralPose.gesture = .idle;neutralPose.gestureTime = 0
                let neutral = PuppetMotion(pose:neutralPose)
                via = neutral
                firstDuration = Self.transitionDuration(from:lastMotion,to:neutral)
                duration = firstDuration+Self.transitionDuration(from:neutral,to:target)
            } else {
                via = nil;firstDuration = 0
                duration = Self.transitionDuration(from:lastMotion,to:target)
            }
        }
        pending = false
        effective = resolved
        var result: PuppetMotion
        var handFrom = previous
        var handTo = target
        var handStart = start
        if let previous {
            if let via, pose.time-start < firstDuration {
                result = via.blended(from:previous,
                    fraction:PuppetMotion.smooth(0,Float(firstDuration),Float(pose.time-start)))
                handTo = via
            } else if let via {
                result = target.blended(from:via,
                    fraction:PuppetMotion.smooth(0,Float(duration-firstDuration),Float(pose.time-start-firstDuration)))
                handFrom = via;handStart += firstDuration
            } else {
                result = target.blended(from: previous,
                    fraction: PuppetMotion.smooth(0, Float(duration), Float(pose.time - start)))
            }
        } else { result = target }
        if let lastPose, let lastMotion {
            let dt = pose.time-lastPose.time
            if dt > 0 && dt < 0.2 {
                let maximum = Float(dt)*Self.maximumHandSpeed
                if Self.maximumStep(lastMotion,result) > maximum {
                    var low: Float = 0, high: Float = 1
                    for _ in 0..<16 {
                        let mid = (low+high)/2
                        if Self.maximumStep(lastMotion,result.blended(from:lastMotion,fraction:mid)) > maximum { high = mid }
                        else { low = mid }
                    }
                    result = result.blended(from:lastMotion,fraction:low)
                }
            }
        }
        if let handFrom {
            let handMotion = handTo.blended(from:handFrom,
                fraction:PuppetMotion.smooth(0,0.22,Float(pose.time-handStart)))
            result.leftHand = handMotion.leftHand;result.rightHand = handMotion.rightHand
            result.leftFist = handMotion.leftFist;result.rightFist = handMotion.rightFist
            result.rightChin = handMotion.rightChin
        }
        result.thoughtOpacity = target.thoughtOpacity
        if resolved == .think {
            let finger = result.armPoint(PuppetMotion.thinkingFinger,shoulder:SIMD2(369,320),
                elbow:SIMD2(427,418),wrist:SIMD2(486,508),left:false)
            let target = result.torsoPoint(result.headPoint(SIMD2(300,268))+SIMD2(1,1))
            let d = finger-target
            if result.rightChin < 0.99 || d.x*d.x+d.y*d.y > 9 { result.thoughtOpacity = 0 }
        }
        if let lastPose,let lastMotion {
            let step = Float(max(0,pose.time-lastPose.time))*4
            result.thoughtOpacity = max(lastMotion.thoughtOpacity-step,
                min(result.thoughtOpacity,lastMotion.thoughtOpacity+step))
        }
        lastPose = pose
        lastMotion = result
        return result
    }
    private static func maximumStep(_ a: PuppetMotion,_ b: PuppetMotion) -> Float {
        var maximum: Float = 0
        for left in [true,false] {
            let shoulder = SIMD2<Float>(left ? 231 : 369,320)
            let elbow = SIMD2<Float>(left ? 173 : 427,418)
            let wrist = SIMD2<Float>(left ? 114 : 486,508)
            for p in [wrist,wrist+SIMD2(left ? -35 : 35,55)] {
                let x = a.armPoint(p,shoulder:shoulder,elbow:elbow,wrist:wrist,left:left)
                let y = b.armPoint(p,shoulder:shoulder,elbow:elbow,wrist:wrist,left:left)
                let d = x-y;maximum = max(maximum,sqrt(d.x*d.x+d.y*d.y))
            }
        }
        return maximum
    }
    /// Estimate peak speed along the actual curved arm path, including both
    /// hands. Endpoint distance alone misses the elbow detour.
    private static func transitionDuration(from: PuppetMotion, to: PuppetMotion) -> Double {
        func points(_ motion: PuppetMotion) -> [SIMD2<Float>] {
            var result: [SIMD2<Float>] = []
            for left in [true,false] {
                let shoulder = SIMD2<Float>(left ? 231 : 369,320)
                let elbow = SIMD2<Float>(left ? 173 : 427,418)
                let wrist = SIMD2<Float>(left ? 114 : 486,508)
                for p in [wrist, wrist + SIMD2(left ? -35 : 35,55)] {
                    result.append(motion.armPoint(p,shoulder:shoulder,elbow:elbow,wrist:wrist,left:left))
                }
            }
            return result
        }
        var before = points(from)
        var peak: Float = 0
        for sample in 1...120 {
            let after = points(to.blended(from:from,fraction:PuppetMotion.smooth(0,1,Float(sample)/120)))
            for (a,b) in zip(before,after) {
                let d = a-b
                peak = max(peak,sqrt(d.x*d.x+d.y*d.y)*120)
            }
            before = after
        }
        return max(0.3,Double(peak/Self.maximumHandSpeed))
    }
}
