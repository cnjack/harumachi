import XCTest
@testable import MioCore

final class NaturalMotionTests: XCTestCase {
    private var assets: URL { URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/MioApp/Resources/MioCubism") }

    func testWebIdleAndSeamlessLoop() throws {
        let manifest = try JSONSerialization.jsonObject(with:Data(contentsOf:assets.appendingPathComponent("Mio.model3.json"))) as! [String:Any]
        let files = manifest["FileReferences"] as! [String:Any]
        let motions = files["Motions"] as! [String:Any]
        XCTAssertNotNil(motions["Idle"],"Cubism 4 web players discover Idle with a capital I")
        XCTAssertNotNil(files["Physics"],"Secondary motion must travel with the model")
        let idle = try JSONSerialization.jsonObject(with:Data(contentsOf:assets.appendingPathComponent("motions/idle.motion3.json"))) as! [String:Any]
        let meta = idle["Meta"] as! [String:Any]
        XCTAssertEqual(meta["Loop"] as? Bool,true)
        XCTAssertGreaterThan(meta["FadeInTime"] as? Double ?? 0,0)
        for curve in idle["Curves"] as! [[String:Any]] {
            let values = curve["Segments"] as! [Double]
            XCTAssertEqual(values[1],values.last!,accuracy:0.0001,"Loop endpoint: \(curve["Id"]!)")
        }
    }

    func testHeadTurnsChangeShapeAndEyesMoveIndependently() throws {
        guard FileManager.default.fileExists(atPath:"/Applications/Live2D Cubism 5.3/res/libLive2DCubismCoreJNI.dylib") else { throw XCTSkip("Official Core is installed separately") }
        let model = try CubismModel(manifest:assets.appendingPathComponent("Mio.model3.json"))
        try model.update([:]);let front = try XCTUnwrap(model.meshes().first {$0.id == "face"})
        try model.update(["ParamAngleX":30]);let turned = try XCTUnwrap(model.meshes().first {$0.id == "face"})
        let dx = stride(from:0,to:front.positions.count,by:2).map { turned.positions[$0]-front.positions[$0] }
        XCTAssertGreaterThan((dx.max() ?? 0)-(dx.min() ?? 0),3,"A head turn must deform the face, not translate it as a card")
        XCTAssertTrue(model.parameters.contains {$0.id == "ParamEyeBallX"})
        try model.update(["ParamEyeBallX":-1]);let left = try model.meshes()
        try model.update(["ParamEyeBallX":1]);let right = try model.meshes()
        let a = try XCTUnwrap(left.first {$0.id == "iris_left"})
        let b = try XCTUnwrap(right.first {$0.id == "iris_left"})
        XCTAssertGreaterThan(zip(a.positions,b.positions).map {abs($0-$1)}.max() ?? 0,1)
        XCTAssertEqual(left.first {$0.id == "face"}?.positions,right.first {$0.id == "face"}?.positions)
        try model.update(["ParamEyeLOpen":0.5]);let half = try XCTUnwrap(model.meshes().first {$0.id == "eye_white_left"})
        try model.update(["ParamEyeLOpen":1]);let open = try XCTUnwrap(model.meshes().first {$0.id == "eye_white_left"})
        XCTAssertGreaterThan(zip(half.positions,open.positions).map {abs($0-$1)}.max() ?? 0,3,"Eyelids need continuous geometry")
    }

    func testHairRespondsToMotionAndSettles() {
        var physics = HairPhysics()
        _ = physics.update([:],time:0)
        let initial = physics.update(["ParamAngleX":30],time:1.0/60)
        XCTAssertEqual(initial,physics.update(["ParamAngleX":30],time:1.0/60),"Snapshot cannot advance physics twice")
        var maximum: Float = 0
        var settled: [String:Float] = [:]
        for frame in 2...300 {
            settled = physics.update([:],time:Double(frame)/60)
            maximum = max(maximum,abs(settled["ParamHairFront"]!))
            XCTAssertTrue(settled.values.allSatisfy(\.isFinite))
        }
        XCTAssertGreaterThan(maximum,0.005)
        XCTAssertLessThan(abs(settled["ParamHairFront"]!),0.0001)
        XCTAssertLessThan(abs(settled["ParamHairBack"]!),0.0001)
    }

    func testWebHandVariantsDoNotCrossfade() throws {
        for name in ["idle","wave","think","talk"] {
            let motion = try JSONSerialization.jsonObject(with:Data(contentsOf:assets.appendingPathComponent("motions/\(name).motion3.json"))) as! [String:Any]
            let hands = (motion["Curves"] as! [[String:Any]]).filter { ["ParamHandL","ParamHandR"].contains($0["Id"] as? String ?? "") }
            XCTAssertEqual(hands.count,2)
            for curve in hands {
                XCTAssertEqual(curve["FadeInTime"] as? Double,0,"\(name): hand IDs must stay discrete during web motion fade")
                XCTAssertEqual(curve["FadeOutTime"] as? Double,0)
            }
        }
    }
}
