import XCTest
@testable import MioCore

final class MotionPlaybackTests: XCTestCase {
    private func wrist(_ m: PuppetMotion, left: Bool = false) -> SIMD2<Float> {
        m.armPoint(SIMD2(left ? 114 : 486,508), shoulder: SIMD2(left ? 231 : 369,320),
            elbow: SIMD2(left ? 173 : 427,418), wrist: SIMD2(left ? 114 : 486,508), left: left)
    }
    private func distance(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let d = a-b; return sqrt(d.x*d.x+d.y*d.y)
    }
    func testAutomaticSpeechInterruptionsDoNotTeleportEitherHand() {
        for start in [2.0,18.0,36.0] {
            var player = MotionPlayback()
            var previous = player.sample(RigPose(time:start))
            for frame in 1...120 {
                let pose = RigPose(time:start+Double(frame)/30, speaking:frame>=10 && frame<25)
                let current = player.sample(pose)
                for left in [true,false] {
                    XCTAssertLessThan(distance(wrist(current,left:left),wrist(previous,left:left)),MotionPlayback.maximumHandSpeed/30+0.01,
                        "Automatic speech start/stop teleports the hand at \(start) frame \(frame)")
                }
                previous = current
            }
        }
    }
    func testAllInterruptionsStayWithinAnActualHandSpeedLimit() {
        let gestures: [CharacterGesture] = [.idle,.wave,.think,.talk]
        for from in gestures { for to in gestures {
            var player = MotionPlayback()
            let before = RigPose(time:2,gesture:from)
            var previous = player.sample(before)
            let phaseOffset = player.select(to,pose:before) ? 0.0 : 2.0
            for frame in 0...150 {
                let current = player.sample(RigPose(time:2+Double(frame)/30,gesture:to,gestureTime:phaseOffset+Double(frame)/30))
                for left in [true,false] {
                    XCTAssertLessThan(distance(wrist(current,left:left),wrist(previous,left:left)),MotionPlayback.maximumHandSpeed/30+0.01,
                        "\(from) -> \(to) too fast at \(frame)")
                }
                previous = current
            }
        } }
    }
    func testRetriggeringAnActiveGestureKeepsItsPhase() {
        for gesture in [CharacterGesture.wave,.think,.talk] {
            var player = MotionPlayback()
            let pose = RigPose(time:2,gesture:gesture)
            _ = player.sample(pose)
            XCTAssertFalse(player.select(gesture,pose:pose),"Do not lower and restart the same active gesture")
        }
    }
    func testThinkingLowersBeforeStartingTheOppositeWaveFold() {
        for start in [2.0,100.0,3600.0] {
            var player = MotionPlayback()
            let pose = RigPose(time:start,gesture:.think,gestureTime:2)
            _ = player.sample(pose)
            _ = player.select(.wave,pose:pose)
            for frame in 0...150 {
                let motion = player.sample(RigPose(time:start+Double(frame)/30,gesture:.wave,gestureTime:Double(frame)/30))
                if motion.rightElbow>0.6 {
                    let resting = PuppetMotion(pose:RigPose(time:start+Double(frame)/30,gesture:.idle))
                    XCTAssertLessThan(abs(motion.leftShoulder-resting.leftShoulder),0.08,"Do not lift the other arm while the thinking elbow folds down, clock \(start)")
                }
            }
        }
    }
}
