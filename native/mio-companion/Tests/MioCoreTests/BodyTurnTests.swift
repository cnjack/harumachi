import XCTest
@testable import MioCore

final class BodyTurnTests: XCTestCase {
    private var assets: URL { ProcessInfo.processInfo.environment["MIO_BODY_FIXTURE"].map { URL(fileURLWithPath:$0) } ?? URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/MioApp/Resources/MioCubism") }
    func testSourceBodyTurnHasPerspectiveAndStableFeetFaceAndJoints() throws {
        guard FileManager.default.fileExists(atPath:"/Applications/Live2D Cubism 5.3/res/libLive2DCubismCoreJNI.dylib") else { throw XCTSkip("Official Core is installed separately") }
        let model=try CubismModel(manifest:assets.appendingPathComponent("Mio.model3.json"))
        XCTAssertTrue(model.parameters.contains {$0.id == "ParamBodyAngleX"},"Body yaw must exist in the exported model")
        let geometry=try JSONDecoder().decode(CubismRigGeometry.self,from:Data(contentsOf:assets.appendingPathComponent("Mio.bindings.json")))
        func meshes() throws -> [String:CubismModel.Mesh] { Dictionary(uniqueKeysWithValues:try model.meshes().map {($0.id,$0)}) }
        func point(_ p: SIMD2<Float>,_ name: String,_ state: [String:CubismModel.Mesh]) throws -> SIMD2<Float> { try geometry.point(p,mesh:XCTUnwrap(state[name])) }
        try model.update([:]);let front=try meshes()
        for yaw: Float in [-10,-6,6,10] {
            try model.update(["ParamBodyAngleX":yaw]);let turned=try meshes()
            let center=try point(SIMD2(300,370),"torso",turned)-point(SIMD2(300,370),"torso",front)
            let edge=try point(SIMD2(380,370),"torso",turned)-point(SIMD2(380,370),"torso",front)
            XCTAssertGreaterThan(center.x*(yaw>0 ? 1:-1),3,"The chest must visibly turn")
            XCTAssertGreaterThan(abs(center.x-edge.x),1.5,"Body yaw must not be a rigid sideways slide")
            XCTAssertEqual(center.y,0,accuracy:0.01,"Horizontal turning does not tilt the chest")
            let head=try point(SIMD2(300,268),"face",turned)-point(SIMD2(300,268),"face",front)
            let neck=try point(SIMD2(300,285),"torso",turned)-point(SIMD2(300,285),"torso",front)
            XCTAssertEqual(head.x,neck.x,accuracy:0.1,"Neck and head must travel together")
            for name in ["face","eyes_open_left","eyes_open_right"] {
                let a=try XCTUnwrap(front[name]),b=try XCTUnwrap(turned[name])
                for i in stride(from:0,to:a.positions.count,by:2) {
                    XCTAssertEqual(b.positions[i]-a.positions[i],head.x,accuracy:0.01,"Body yaw cannot distort the accepted face")
                    XCTAssertEqual(b.positions[i+1],a.positions[i+1],accuracy:0.01)
                }
            }
            for p: SIMD2<Float> in [SIMD2(275,700),SIMD2(325,800),SIMD2(260,940),SIMD2(340,940)] {
                let a=try point(p,"lower_body",front),b=try point(p,"lower_body",turned)
                XCTAssertEqual(a.x,b.x,accuracy:0.001);XCTAssertEqual(a.y,b.y,accuracy:0.001,"Feet and lower legs stay planted")
            }
            for (side,x) in [("left",Float(114)),("right",Float(486))] {
                let wrist=SIMD2<Float>(x,508)
                let arm=try point(wrist,"forearm_"+side,turned),hand=try point(wrist,"hand_"+side+"_relaxed",turned)
                XCTAssertEqual(arm.x,hand.x,accuracy:0.01);XCTAssertEqual(arm.y,hand.y,accuracy:0.01)
            }
        }
    }
    func testFollowStaysSubtleAndThinkingContactSurvives() {
        for x: Float in [-1,0,1] {
            let pose=RigPose(time:2,lookX:x,gesture:.think,gestureTime:2),m=PuppetMotion(pose:pose)
            XCTAssertLessThanOrEqual(abs(m.torsoYaw),6)
            let chin=m.torsoPoint(m.headPoint(SIMD2(300,268))+SIMD2(1,1))
            let finger=m.armPoint(PuppetMotion.thinkingFinger,shoulder:SIMD2(369,320),elbow:SIMD2(427,418),wrist:SIMD2(486,508),left:false,hand:true)
            let delta=chin-finger
            XCTAssertLessThan(sqrt(delta.x*delta.x+delta.y*delta.y),0.3)
        }
    }
}
