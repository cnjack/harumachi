import XCTest
@testable import MioCore

final class CardiganWidthTests: XCTestCase {
    func testOfficialGarmentNarrowsWithoutChangingSkinOrJointAnchors() throws {
        guard FileManager.default.fileExists(atPath:"/Applications/Live2D Cubism 5.3/res/libLive2DCubismCoreJNI.dylib") else { throw XCTSkip("Official Core is installed separately") }
        let directory = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/MioApp/Resources/MioCubism")
        let model = try CubismModel(manifest:directory.appendingPathComponent("Mio.model3.json"))
        let geometry = try JSONDecoder().decode(CubismRigGeometry.self,from:Data(contentsOf:directory.appendingPathComponent("Mio.bindings.json")))
        let neutral: [String:Float] = ["ParamShoulderL":0,"ParamShoulderR":0,"ParamElbowL":0,"ParamElbowR":0]
        try model.update(neutral)
        let meshes = Dictionary(uniqueKeysWithValues:try model.meshes().map { ($0.id,$0) })
        func point(_ p: SIMD2<Float>,_ id: String) throws -> SIMD2<Float> { try geometry.point(p,mesh:XCTUnwrap(meshes[id])) }
        func distance(_ a: SIMD2<Float>,_ b: SIMD2<Float>) -> Float { let d=a-b;return sqrt(d.x*d.x+d.y*d.y) }
        let leftEdge = try point(SIMD2(195,425),"torso"),rightEdge = try point(SIMD2(405,425),"torso")
        XCTAssertEqual(rightEdge.x-leftEdge.x,205,accuracy:0.1,"Keep more of the original 210-wide torso; v26 over-tapered it to 202")
        for p: SIMD2<Float> in [SIMD2(300,285),SIMD2(300,370),SIMD2(270,400),SIMD2(330,400)] {
            XCTAssertLessThan(try distance(point(p,"torso"),p+SIMD2(75,0)),0.03,"Keep neck and central blouse intact")
        }
        for left in [true,false] {
            let side = left ? "left":"right"
            let s=SIMD2<Float>(left ? 231:369,320),e=SIMD2<Float>(left ? 173:427,418),w=SIMD2<Float>(left ? 114:486,508)
            for (id,start,end,along) in [("arm_"+side,s,e,Float(55)),("lower_sleeve_"+side,e,w,Float(27))] {
                let axis=end-start,d=axis/sqrt(axis.x*axis.x+axis.y*axis.y),n=SIMD2(-d.y,d.x)
                let center=start+d*along
                let width=try distance(point(center+n*20,id),point(center-n*20,id))
                XCTAssertGreaterThan(width,36.5,"Keep at least 91% of loose fabric width; skin remains unchanged")
                XCTAssertLessThan(width,38.6,"The old sleeve span is 40; only fabric narrows")
            }
            // v26 narrowed only the sleeve shafts while leaving both elbow
            // caps full-sized. Match their fabric widths to remove that bulge.
            for (id,axis) in [("arm_"+side,e-s),("lower_sleeve_"+side,w-e)] {
                let d=axis/sqrt(axis.x*axis.x+axis.y*axis.y),n=SIMD2(-d.y,d.x)
                let width=try distance(point(e+n*20,id),point(e-n*20,id))
                XCTAssertEqual(width,36.8,accuracy:0.12,"The upper and lower elbow artwork must narrow together")
            }
            for (id,p) in [("arm_"+side,s),("arm_"+side,e),("lower_sleeve_"+side,e),("forearm_"+side,w)] {
                XCTAssertLessThan(try distance(point(p,id),p+SIMD2(75,0)),0.04,"Do not move shoulder/elbow/wrist anchors")
            }
            let axis=w-e,d=axis/sqrt(axis.x*axis.x+axis.y*axis.y),n=SIMD2(-d.y,d.x)
            for along: Float in [58,80,100] {
                let center=e+d*along
                XCTAssertEqual(try distance(point(center+n*12,"forearm_"+side),point(center-n*12,"forearm_"+side)),24,accuracy:0.03,"Bare arm thickness is unchanged")
            }
        }
        // Local release QA can compare every unaffected vertex against the
        // immediately preceding official export, across all gestures and yaw.
        if let path=ProcessInfo.processInfo.environment["MIO_CARDIGAN_BASELINE"] {
            let previous=try CubismModel(manifest:URL(fileURLWithPath:path).appendingPathComponent("Mio.model3.json"))
            let changed:Set<String>=["torso","arm_left","arm_right","lower_sleeve_left","lower_sleeve_right"]
            for gesture in [CharacterGesture.idle,.wave,.think,.talk,.encourage] { for look: Float in [-1,0,1] {
                let pose=RigPose(time:2,lookX:look,gesture:gesture,gestureTime:2),motion=PuppetMotion(pose:pose)
                let values=CubismParameters.values(pose:pose,motion:motion)
                try model.update(values);try previous.update(values)
                let before=Dictionary(uniqueKeysWithValues:try previous.meshes().map { ($0.id,$0) })
                for mesh in try model.meshes() where !changed.contains(mesh.id) {
                    let original=try XCTUnwrap(before[mesh.id])
                    XCTAssertEqual(mesh.positions.count,original.positions.count)
                    for (a,b) in zip(mesh.positions,original.positions) { XCTAssertEqual(a,b,accuracy:0.0001,"Unchanged \(mesh.id) \(gesture) / \(look)") }
                }
            } }
        }
    }
}
