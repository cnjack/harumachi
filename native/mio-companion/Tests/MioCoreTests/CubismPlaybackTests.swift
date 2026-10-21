import XCTest
@testable import MioCore

final class CubismPlaybackTests: XCTestCase {
    private var assets: URL { URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/MioApp/Resources/MioCubism") }
    func testMotionCurveTypesAndBezierTime() throws {
        func curve(_ values: [Double]) throws -> CubismMotion {
            let data=try JSONSerialization.data(withJSONObject:["Meta":["Duration":1,"Loop":false],"Curves":[["Target":"Parameter","Id":"x","Segments":values]]])
            return try CubismMotion(data:data)
        }
        XCTAssertEqual(try curve([0,0,0,1,1]).sample(0.25)["x"]!,0.25,accuracy:0.001)
        XCTAssertEqual(try curve([0,0,2,1,1]).sample(0.5)["x"]!,0)
        XCTAssertEqual(try curve([0,0,3,1,1]).sample(0.5)["x"]!,1)
        // x(t) differs from t: a linear-in-time shortcut would return .5.
        let value=try curve([0,0,1,0.1,0,0.1,1,1,1]).sample(0.5)["x"]!
        XCTAssertGreaterThan(value,0.8);XCTAssertLessThan(value,0.9)
        XCTAssertThrowsError(try curve([0,0,4,1,1]))
    }
    func testAuthoredMotionDrivesPlayback() throws {
        let library=try MotionLibrary(directory:assets)
        for gesture in [CharacterGesture.idle,.wave,.talk] {
            let pose=RigPose(time:1.7,gesture:gesture,gestureTime:1.7)
            var playback=MotionPlayback(library:library)
            let motion=playback.sample(pose),values=library.motions[gesture.rawValue]!.sample(1.7)
            XCTAssertEqual(motion.rightElbow,values["ParamElbowR"]!,accuracy:0.00001)
            XCTAssertEqual(motion.rightShoulder,values["ParamShoulderR"]!,accuracy:0.00001)
        }
    }
    func testPhysicsReadsFileAndRespondsThenSettles() throws {
        let parameters=[("ParamAngleX",Float(30)),("ParamAngleZ",12),("ParamBodyAngleZ",3),("ParamHairFront",1),("ParamHairBack",1)].map { CubismModel.Parameter(id:$0.0,minimum:-$0.1,maximum:$0.1,value:0) }
        let data=try Data(contentsOf:assets.appendingPathComponent("Mio.physics3.json"))
        var physics=try CubismPhysics(data:data,parameters:parameters),maxValue: Float=0,last: [String:Float]=[:]
        _=physics.update([:],time:0)
        for frame in 1...600 {
            last=physics.update(["ParamAngleX":frame<60 ? 20:0],time:Double(frame)/60)
            maxValue=max(maxValue,abs(last["ParamHairFront"]!))
            XCTAssertTrue(last.values.allSatisfy(\.isFinite))
        }
        XCTAssertGreaterThan(maxValue,0.05)
        XCTAssertLessThan(abs(last["ParamHairFront"]!),0.001)
        XCTAssertEqual(last,physics.update(["ParamAngleX":0],time:10),"Repeated snapshot must not advance the strand")
        let zeroScale=String(data:data,encoding:.utf8)!.replacingOccurrences(of:"\"Scale\": 1.2",with:"\"Scale\": 0")
        var disabled=try CubismPhysics(data:Data(zeroScale.utf8),parameters:parameters)
        for frame in 0...60 { XCTAssertEqual(disabled.update(["ParamAngleX":20],time:Double(frame)/60)["ParamHairFront"]!,0) }
    }
}
