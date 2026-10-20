import XCTest
@testable import MioCore

final class HandPresentationTests: XCTestCase {
    func testTurningAndClosingDoNotFoldTheWristMesh() {
        let wrist = SIMD2<Float>(486,508), elbow = SIMD2<Float>(427,418)
        let axis = wrist-elbow, d = axis/sqrt(axis.x*axis.x+axis.y*axis.y), n = SIMD2(-d.y,d.x)
        for variant in 1...5 {
            for step in 0...100 {
                let fraction = Float(step)/100
                var motion = PuppetMotion(pose:RigPose(time:0,gesture:.idle))
                motion.rightHand = SIMD4(1-fraction,0,0,0)
                if variant<4 { motion.rightHand[variant] = fraction }
                else if variant == 4 { motion.rightFist = fraction }
                else { motion.rightChin = fraction }
                let hand = HandPresentation(motion:motion,left:false)
                XCTAssertEqual(hand.point(wrist,elbow:elbow,wrist:wrist),wrist)
                XCTAssertEqual(hand.point(wrist-d*20+n*8,elbow:elbow,wrist:wrist),wrist-d*20+n*8)
                for along in stride(from:Float(0),through:30,by:1) {
                    let p = wrist+d*along
                    let a = hand.point(p,elbow:elbow,wrist:wrist)
                    let b = hand.point(p+d,elbow:elbow,wrist:wrist)
                    let c = hand.point(p+n,elbow:elbow,wrist:wrist)
                    let u = b-a,v = c-a
                    XCTAssertGreaterThan(u.x*v.y-u.y*v.x,0.01,"Hand mesh reverses at \(variant),\(step),\(along)")
                }
            }
        }
    }
}
