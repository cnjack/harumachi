import XCTest
@testable import MioCore

final class ArticulationTests: XCTestCase {
    func testIndependentArmsHaveThreeJoints() throws {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf:
            package.appendingPathComponent("Sources/MioApp/Resources/Mio/Mio.rig.json"))) as! [String: Any]
        let layers = json["layers"] as! [[String: Any]]
        for id in ["arm_left", "arm_right"] {
            let arm = try XCTUnwrap(layers.first { $0["id"] as? String == id }, "Arms need independent artwork to bend without pulling the torso")
            let joints = try XCTUnwrap(arm["joints"] as? [[Double]])
            XCTAssertEqual(joints.count, 3)
            XCTAssertTrue(joints.allSatisfy { $0.count == 2 })
            XCTAssertGreaterThan(joints[2][1], joints[1][1])
            XCTAssertGreaterThan(joints[1][1], joints[0][1])
        }
    }
    func testNeckConnectsHeadToFixedCollarContinuously() {
        let motion = PuppetMotion(pose: RigPose(time: 2, lookX: 1, lookY: 1, gesture: .think))
        let upper = SIMD2<Float>(300, 270), collar = SIMD2<Float>(300, 310)
        XCTAssertEqual(motion.neckPoint(upper), motion.headPoint(upper))
        XCTAssertEqual(motion.neckPoint(collar), collar)
        let middle = SIMD2<Float>(300, 291)
        XCTAssertGreaterThan(abs(motion.neckPoint(middle).x - middle.x), 0.5)
        for y in 270..<312 {
            let a = motion.neckPoint(SIMD2(300, Float(y)))
            let b = motion.neckPoint(SIMD2(300, Float(y + 1)))
            XCTAssertLessThan(abs(b.x - a.x), 1)
            XCTAssertLessThan(abs(b.y - a.y), 1.5)
        }
    }
    func testGesturesEaseInAndReturnWithoutSnapping() {
        let old = PuppetMotion(pose: RigPose(time: 2, gesture: .wave))
        let next = PuppetMotion(pose: RigPose(time: 0, gesture: .stretch))
        XCTAssertEqual(next.blended(from: old, fraction: 0).rightElbow, old.rightElbow)
        XCTAssertEqual(next.blended(from: old, fraction: 1).rightElbow, next.rightElbow)
        XCTAssertEqual(next.blended(from: old, fraction: 0.5).rightElbow, (old.rightElbow + next.rightElbow) / 2, accuracy: 0.0001)
        for gesture in CharacterGesture.allCases where gesture != .automatic {
            XCTAssertEqual(PuppetMotion.envelope(0, duration: gesture.duration), 0)
            XCTAssertEqual(PuppetMotion.envelope(gesture.duration, duration: gesture.duration), 0)
            XCTAssertEqual(PuppetMotion.envelope(2, duration: gesture.duration), 1)
            let resting = PuppetMotion(pose: RigPose(time: gesture.duration, gesture: .idle))
            let end = PuppetMotion(pose: RigPose(time: gesture.duration, gesture: gesture))
            XCTAssertEqual(end.head, resting.head, accuracy: 0.0001)
            XCTAssertEqual(end.rightShoulder, resting.rightShoulder, accuracy: 0.0001)
        }
    }
    func testWaveMovesHandWhileKeepingShoulderAttached() {
        let shoulder = SIMD2<Float>(362, 310), elbow = SIMD2<Float>(432, 405), wrist = SIMD2<Float>(483, 510)
        let idle = PuppetMotion(pose: RigPose(time: 2, gesture: .idle))
        let wave = PuppetMotion(pose: RigPose(time: 2, gesture: .wave))
        let raised = wave.armPoint(wrist, shoulder: shoulder, elbow: elbow, wrist: wrist, left: false)
        let lowered = idle.armPoint(wrist, shoulder: shoulder, elbow: elbow, wrist: wrist, left: false)
        XCTAssertLessThan(raised.y, lowered.y - 160)
        XCTAssertEqual(wave.armPoint(shoulder, shoulder: shoulder, elbow: elbow, wrist: wrist, left: false), wave.torsoPoint(shoulder))
        for gesture in [CharacterGesture.wave, .stretch, .think, .talk] {
            for frame in 0...210 {
                let pose = RigPose(time: Double(frame) / 30, gesture: gesture)
                let motion = PuppetMotion(pose: pose)
                let hand = motion.armPoint(SIMD2(535, 565), shoulder: shoulder, elbow: elbow, wrist: wrist, left: false)
                let leftHand = motion.armPoint(SIMD2(65, 565), shoulder: SIMD2(238, 310), elbow: SIMD2(168, 405), wrist: SIMD2(117, 510), left: true)
                XCTAssertTrue((5...595).contains(leftHand.x) && (5...995).contains(leftHand.y), "Left hand cropped during \(gesture) frame \(frame): \(leftHand)")
                XCTAssertTrue(hand.x.isFinite && hand.y.isFinite)
                XCTAssertTrue((5...595).contains(hand.x) && (5...995).contains(hand.y), "Hand cropped during \(gesture) frame \(frame): \(hand)")
            }
        }
    }
}
