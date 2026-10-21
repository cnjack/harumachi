import XCTest
@testable import MioCore

final class ArmAnatomyTests: XCTestCase {
    func testGripStartsWithoutAHandLengthJump() {
        var before=PuppetMotion(pose:RigPose(time:0,gesture:.idle)),after=before
        before.rightHand=SIMD4(0.9,0.09991,0,0);before.rightFist=0.00009
        after.rightHand=SIMD4(0.9,0.09989,0,0);after.rightFist=0.00011
        let e=SIMD2<Float>(427,418),w=SIMD2<Float>(486,508),p=SIMD2<Float>(525,568)
        let a=HandPresentation(motion:before,left:false).point(p,elbow:e,wrist:w)
        let b=HandPresentation(motion:after,left:false).point(p,elbow:e,wrist:w),d=a-b
        XCTAssertLessThan(sqrt(d.x*d.x+d.y*d.y),0.1,"Grip onset must not switch abruptly between two hand lengths")
    }
    func testHandCompressionKeepsTheWholeWristNeighbourhoodFixed() {
        var motion=PuppetMotion(pose:RigPose(time:0,gesture:.idle))
        motion.rightHand=SIMD4(0.81,0,0,0);motion.rightFist=0.19
        let e=SIMD2<Float>(427,418),w=SIMD2<Float>(486,508),axis=w-e
        let d=axis/sqrt(axis.x*axis.x+axis.y*axis.y),n=SIMD2(-d.y,d.x)
        let hand=HandPresentation(motion:motion,left:false)
        for along in stride(from:Float(-12),through:12,by:3) { for across in [Float(-10),0,10] {
            let p=w+d*along+n*across,q=hand.point(p,elbow:e,wrist:w)
            XCTAssertEqual(p.x,q.x,accuracy:0.0001);XCTAssertEqual(p.y,q.y,accuracy:0.0001)
        } }
    }
    func testBoneSegmentsKeepLengthAndRemainStraight() {
        func distance(_ a: SIMD2<Float>,_ b: SIMD2<Float>) -> Float { let d=a-b;return sqrt(d.x*d.x+d.y*d.y) }
        for gesture in [CharacterGesture.idle,.wave,.think,.talk] {
            for frame in stride(from:0,through:210,by:5) {
                let m=PuppetMotion(pose:RigPose(time:Double(frame)/30,gesture:gesture))
                for left in [true,false] {
                    let s=SIMD2<Float>(left ? 231:369,320),e=SIMD2<Float>(left ? 173:427,418),w=SIMD2<Float>(left ? 114:486,508)
                    func p(_ q: SIMD2<Float>) -> SIMD2<Float> { m.armPoint(q,shoulder:s,elbow:e,wrist:w,left:left) }
                    XCTAssertEqual(distance(p(s),p(e)),distance(s,e),accuracy:0.05,"Upper bone length: \(gesture) \(frame)")
                    XCTAssertEqual(distance(p(e),p(w)),distance(e,w),accuracy:0.05,"Forearm bone length: \(gesture) \(frame)")
                    XCTAssertEqual(distance(p((s+e)/2),(p(s)+p(e))/2),0,accuracy:0.05,"Upper arm must have a straight centreline")
                    XCTAssertLessThan(abs(left ? m.leftElbow:m.rightElbow),Float.pi,"No elbow may wrap through a full turn")
                }
            }
        }
    }
}
