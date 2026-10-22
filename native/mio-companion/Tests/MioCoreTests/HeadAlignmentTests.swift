import XCTest
@testable import MioCore

final class HeadAlignmentTests: XCTestCase {
    private var assets: URL { ProcessInfo.processInfo.environment["MIO_HEAD_FIXTURE"].map { URL(fileURLWithPath:$0) } ?? URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/MioApp/Resources/MioCubism") }

    func testIdleDoesNotContinuallyTiltEyeLine() throws {
        let library=try MotionLibrary(directory:assets)
        for time in stride(from:0.0,through:20,by:0.25) {
            let pose=RigPose(time:time,lookX:1,lookY:1,gesture:.idle)
            XCTAssertEqual(PuppetMotion(pose:pose).head,0,accuracy:0.0001)
            XCTAssertEqual(library.motion(for:pose).head,0,accuracy:0.0001,"Idle motion must not reintroduce automatic roll")
        }
    }

    func testExportedYawKeepsNeckUprightAndEyesLevel() throws {
        guard FileManager.default.fileExists(atPath:"/Applications/Live2D Cubism 5.3/res/libLive2DCubismCoreJNI.dylib") else { throw XCTSkip("Official Core is installed separately") }
        let model=try CubismModel(manifest:assets.appendingPathComponent("Mio.model3.json"))
        let geometry=try JSONDecoder().decode(CubismRigGeometry.self,from:Data(contentsOf:assets.appendingPathComponent("Mio.bindings.json")))
        func point(_ x: Float,_ y: Float,_ name: String) throws -> SIMD2<Float> {
            let mesh=try XCTUnwrap(model.meshes().first {$0.id==name})
            return try geometry.point(SIMD2(x,y),mesh:mesh)
        }
        try model.update([:])
        let chin=try point(300,268,"face"),neck=try point(300,285,"torso")
        let collar=try point(300,310,"torso")
        let eyeL=try point(323,205,"eyes_open_left"),eyeR=try point(277,205,"eyes_open_right")
        for yaw: Float in [-30,-15,0,15,30] { for pitch: Float in [-30,0,30] {
            try model.update(["ParamAngleX":yaw,"ParamAngleY":pitch,"ParamAngleZ":0,"ParamBodyAngleZ":0])
            XCTAssertLessThan(abs(try point(300,268,"face").x-chin.x),7.5,"Turning the face must not translate the jaw off the neck")
            XCTAssertLessThan(abs(try point(300,285,"torso").x-neck.x),5,"Do not shear the visible neck into a diagonal strip")
            XCTAssertEqual(try point(300,310,"torso").x,collar.x,accuracy:0.1,"The collar remains anchored")
            let l=try point(323,205,"eyes_open_left"),r=try point(277,205,"eyes_open_right")
            XCTAssertEqual((l.y-r.y)-(eyeL.y-eyeR.y),0,accuracy:0.1,"Yaw/pitch must not raise one eye over the other")
            XCTAssertLessThan(abs((l.x+r.x-eyeL.x-eyeR.x)/2),12,"Eye sockets must remain centered within the turning face")
        } }
    }
}
