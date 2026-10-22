import XCTest
@testable import MioCore

final class NaturalMotionTests: XCTestCase {
    private var assets: URL { ProcessInfo.processInfo.environment["MIO_TURN_FIXTURE"].map { URL(fileURLWithPath:$0) } ?? URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/MioApp/Resources/MioCubism") }

    func testHorizontalLookTurnsWithoutAddingRoll() throws {
        let library = try MotionLibrary(directory:assets)
        for gesture in [CharacterGesture.idle,.wave,.think,.talk,.encourage] {
            let a = RigPose(time:2,lookX:-1,gesture:gesture,gestureTime:2)
            let b = RigPose(time:2,lookX:1,gesture:gesture,gestureTime:2)
            for (left,right) in [(PuppetMotion(pose:a),PuppetMotion(pose:b)),(library.motion(for:a),library.motion(for:b))] {
                XCTAssertEqual(left.head,right.head,accuracy:0.0001,"Horizontal attention must turn the face, not tilt the ear toward the shoulder")
                let l=CubismParameters.values(pose:a,motion:left),r=CubismParameters.values(pose:b,motion:right)
                XCTAssertLessThan(l["ParamAngleX"]!,-20);XCTAssertGreaterThan(r["ParamAngleX"]!,20)
            }
        }
    }

    func testOfficialYawHasVisibleFacialPerspectiveWithoutEyeLineTilt() throws {
        guard FileManager.default.fileExists(atPath:"/Applications/Live2D Cubism 5.3/res/libLive2DCubismCoreJNI.dylib") else { throw XCTSkip("Official Core is installed separately") }
        let model=try CubismModel(manifest:assets.appendingPathComponent("Mio.model3.json"))
        let geometry=try JSONDecoder().decode(CubismRigGeometry.self,from:Data(contentsOf:assets.appendingPathComponent("Mio.bindings.json")))
        try model.update([:]);let front=try XCTUnwrap(model.meshes().first {$0.id == "face"})
        func point(_ x: Float,_ y: Float,_ mesh: CubismModel.Mesh) throws -> SIMD2<Float> { try geometry.point(SIMD2(x,y),mesh:mesh) }
        for yaw: Float in [-30,30] {
            try model.update(["ParamAngleX":yaw,"ParamAngleY":0,"ParamAngleZ":0])
            let face=try XCTUnwrap(model.meshes().first {$0.id == "face"})
            let centerShift=try point(300,214,face)-point(300,214,front)
            let cheekMid=try (point(245,214,face)+point(355,214,face))/2
            let originalCheekMid=try (point(245,214,front)+point(355,214,front))/2
            let sideShift=cheekMid-originalCheekMid
            // A readable small turn does not require moving the whole face
            // 14+ pixels away from its neck (the rejected v20 behavior).
            XCTAssertGreaterThan(centerShift.x*(yaw>0 ? 1:-1),8,"The face must visibly turn toward the requested side")
            XCTAssertGreaterThan(abs(centerShift.x-sideShift.x),3,"A rigid sideways slide does not provide face perspective")
            let leftWidth=try point(286,205,face).x-point(268,205,face).x
            let rightWidth=try point(332,205,face).x-point(314,205,face).x
            let ratio=yaw>0 ? rightWidth/leftWidth:leftWidth/rightWidth
            XCTAssertTrue((0.78...0.96).contains(ratio),"A moderate turn needs mild facial perspective without crushing the far side: \(ratio)")
            let eyeLine=try point(323,205,face).y-point(277,205,face).y
            XCTAssertEqual(eyeLine,0,accuracy:0.1,"Pure horizontal yaw keeps the eye line level")
        }
    }

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

    func testSourceHeadHasCoherentYawAndPreservedPitch() throws {
        guard FileManager.default.fileExists(atPath:"/Applications/Live2D Cubism 5.3/res/libLive2DCubismCoreJNI.dylib") else { throw XCTSkip("Official Core is installed separately") }
        let model = try CubismModel(manifest:assets.appendingPathComponent("Mio.model3.json"))
        try model.update([:]);let front = try XCTUnwrap(model.meshes().first {$0.id == "face"})
        for x: Float in [-30,30] { for y: Float in [-30,30] {
            try model.update(["ParamAngleX":x,"ParamAngleY":y])
            let turned = try XCTUnwrap(model.meshes().first {$0.id == "face"})
            for axis in 0...1 {
                let delta = stride(from:axis,to:front.positions.count,by:2).map { turned.positions[$0]-front.positions[$0] }
                let spread=(delta.max() ?? 0)-(delta.min() ?? 0)
                XCTAssertGreaterThan(spread,0.5,"Turning needs source surface depth, not only translation")
                XCTAssertLessThan(spread,axis == 0 ? 40:4,"Yaw changes perspective; pitch keeps its accepted range")
            }
        } }
    }

    func testTurnPreservesNeutralAndHasNoPinnedChin() {
        let landmarks: [SIMD2<Float>] = [SIMD2(300,268),SIMD2(277,205),SIMD2(323,205),SIMD2(270,230),SIMD2(330,230)]
        for p in landmarks { XCTAssertEqual(FaceRig.turn(p,x:0,y:0),p) }
        let chin=FaceRig.turn(landmarks[0],x:30,y:30)-landmarks[0]
        XCTAssertGreaterThan(abs(chin.x)+abs(chin.y),0.5)
        for x: Float in [-30,0,30] { for y: Float in [-30,0,30] {
            let a=FaceRig.turn(landmarks[1],x:x,y:y),b=FaceRig.turn(landmarks[2],x:x,y:y)
            XCTAssertTrue((40...46.001).contains(b.x-a.x),"Turned eye separation stays within the original face proportions")
            XCTAssertEqual(a.y,b.y,accuracy:0.001,"Do not skew one eye above the other")
        } }
    }

    func testOriginalEyesRetainTheirLayoutAndGazeStaysSubtle() throws {
        let bindings = try JSONSerialization.jsonObject(with:Data(contentsOf:assets.appendingPathComponent("Mio.bindings.json"))) as! [String:Any]
        let meshes = bindings["meshes"] as! [[String:Any]]
        for side in ["left","right"] {
            let eye = try XCTUnwrap(meshes.first {$0["id"] as? String == "eyes_open_"+side},"Use the original rounded eye artwork")
            let rect = eye["rect"] as! [Double]
            XCTAssertEqual(rect[0],257.312,accuracy:0.001)
            XCTAssertEqual(rect[1],187.04,accuracy:0.001)
            XCTAssertEqual(rect[2]/rect[3],2.59857,accuracy:0.001)
        }
        guard FileManager.default.fileExists(atPath:"/Applications/Live2D Cubism 5.3/res/libLive2DCubismCoreJNI.dylib") else { throw XCTSkip("Official Core is installed separately") }
        let model = try CubismModel(manifest:assets.appendingPathComponent("Mio.model3.json"))
        try model.update(["ParamEyeBallX":-1]);let left = try model.meshes()
        try model.update(["ParamEyeBallX":1]);let right = try model.meshes()
        let a = try XCTUnwrap(left.first {$0.id == "eyes_iris_left"})
        let b = try XCTUnwrap(right.first {$0.id == "eyes_iris_left"})
        let delta = zip(a.positions,b.positions).map {abs($0-$1)}.max() ?? 0
        XCTAssertGreaterThan(delta,0.2);XCTAssertLessThan(delta,2.5)
        XCTAssertEqual(left.first {$0.id == "face"}?.positions,right.first {$0.id == "face"}?.positions)
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
        for name in ["idle","wave","think","talk","encourage"] {
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
