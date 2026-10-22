import XCTest
@testable import MioCore

final class CubismTests: XCTestCase {
    private var assets: URL { URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/MioApp/Resources/MioCubism") }
    func testRejectsLegacyRigAsCubism() throws {
        let url = assets.deletingLastPathComponent().appendingPathComponent("Mio/Mio.rig.json")
        XCTAssertThrowsError(try JSONDecoder().decode(CubismModel.Manifest.self,from:Data(contentsOf:url)))
    }
    func testResourcePathsAndMissingTextures() throws {
        for path in ["../Mio/Mio.rig.json","/etc/passwd","https://example.com/moc","textures/../../Mio.moc3","missing.png"] {
            XCTAssertThrowsError(try CubismModel.resource(path,inside:assets),path)
        }
        XCTAssertNoThrow(try CubismModel.resource("textures/texture_00.png",inside:assets))
    }
    func testStandardMotionCountsAndIDs() throws {
        let display = try JSONSerialization.jsonObject(with:Data(contentsOf:assets.appendingPathComponent("Mio.cdi3.json"))) as! [String:Any]
        let ids = Set((display["Parameters"] as! [[String:Any]]).map { $0["Id"] as! String })
        XCTAssertEqual(ids.count,38)
        for name in ["idle","wave","think","talk","encourage"] {
            let motion = try JSONSerialization.jsonObject(with:Data(contentsOf:assets.appendingPathComponent("motions/\(name).motion3.json"))) as! [String:Any]
            XCTAssertEqual(motion["Version"] as? Int,3)
            let curves = motion["Curves"] as! [[String:Any]],meta = motion["Meta"] as! [String:Any]
            XCTAssertEqual(Set(curves.map { $0["Id"] as! String }),ids)
            var segmentCount = 0,pointCount = 0
            for curve in curves {
                let segments = curve["Segments"] as! [Double]
                XCTAssertEqual((segments.count-2)%3,0)
                segmentCount += (segments.count-2)/3;pointCount += (segments.count-2)/3+1
                let hand = ["ParamHandL","ParamHandR"].contains(curve["Id"] as! String)
                for i in stride(from:2,to:segments.count,by:3) {
                    XCTAssertGreaterThan(segments[i+1],i==2 ? 0 : segments[i-2])
                    if hand { XCTAssertEqual(segments[i],2,"Hand art switches use stepped segments") }
                }
            }
            XCTAssertEqual(meta["TotalSegmentCount"] as? Int,segmentCount)
            XCTAssertEqual(meta["TotalPointCount"] as? Int,pointCount)
        }
    }
    func testEncouragementForearmLeansTowardFace() throws {
        let library=try MotionLibrary(directory:assets)
        for time in [1.5,2.5,3.5] {
            let pose=RigPose(time:time,gesture:.encourage,gestureTime:time)
            for motion in [PuppetMotion(pose:pose),library.motion(for:pose)] {
                let s=SIMD2<Float>(369,320),e=SIMD2<Float>(427,418),w=SIMD2<Float>(486,508)
                let elbow=motion.armPoint(e,shoulder:s,elbow:e,wrist:w,left:false)
                let wrist=motion.armPoint(w,shoulder:s,elbow:e,wrist:w,left:false)
                XCTAssertLessThan(wrist.x,elbow.x-12,"Encouragement should bring the wrist inward toward the face")
                XCTAssertLessThan(wrist.y,elbow.y-80,"Keep a raised supportive fist, not a horizontal punch")
            }
        }
    }
    func testOfficialCoreAndCorruptMoc() throws {
        let core = "/Applications/Live2D Cubism 5.3/res/libLive2DCubismCoreJNI.dylib"
        guard FileManager.default.fileExists(atPath:core) else { throw XCTSkip("Separately installed official Cubism Core required") }
        let model = try CubismModel(manifest:assets.appendingPathComponent("Mio.model3.json"))
        XCTAssertEqual(model.parameters.count,38);XCTAssertEqual(try model.meshes().count,58)
        XCTAssertEqual(model.mocVersion,3)
        for parameter in model.parameters {
            var values: [String:Float] = ["ParamHandOpenL":0,"ParamHandOpenR":0];values[parameter.id]=parameter.minimum
            try model.update(values);let low = try model.meshes()
            values[parameter.id]=parameter.maximum;try model.update(values);let high = try model.meshes()
            let changed = zip(low,high).contains { a,b in
                abs(a.opacity-b.opacity)>0.0001 || zip(a.positions,b.positions).contains { abs($0-$1)>0.0001 }
            }
            XCTAssertTrue(changed,"Unbound \(parameter.id)")
        }
        let topology=try JSONDecoder().decode(CubismRigGeometry.self,from:Data(contentsOf:assets.appendingPathComponent("Mio.bindings.json")))
        func distance(_ a: SIMD2<Float>,_ b: SIMD2<Float>) -> Float {let d=a-b;return sqrt(d.x*d.x+d.y*d.y)}
        for gesture in [CharacterGesture.idle,.wave,.think,.talk,.encourage] {
            for frame in stride(from:0,through:Int(gesture.duration*30),by:1) {
                let pose=RigPose(time:Double(frame)/30,gesture:gesture),motion=PuppetMotion(pose:pose)
                try model.update(CubismParameters.values(pose:pose,motion:motion))
                let output=try model.meshes(),byID=Dictionary(uniqueKeysWithValues:output.map { ($0.id,$0) })
                for left in [true,false] {
                    let side=left ? "left":"right",s=SIMD2<Float>(left ? 231:369,320),e=SIMD2<Float>(left ? 173:427,418),w=SIMD2<Float>(left ? 114:486,508)
                    let upper=try XCTUnwrap(byID["arm_"+side]),lower=try XCTUnwrap(byID["lower_sleeve_"+side]),skin=try XCTUnwrap(byID["forearm_"+side])
                    let a=try topology.point(s,mesh:upper),b=try topology.point(e,mesh:upper),c=try topology.point(e,mesh:lower),d=try topology.point(w,mesh:skin)
                    XCTAssertEqual(distance(a,b),distance(s,e),accuracy:0.01)
                    XCTAssertEqual(distance(c,d),distance(e,w),accuracy:0.01)
                    XCTAssertLessThan(distance(b,c),0.01,"Official Core elbow attachment")
                    let selected=try XCTUnwrap(output.first { $0.id.hasPrefix("hand_"+side) && $0.opacity>0.001 })
                    XCTAssertLessThan(distance(d,try topology.point(w,mesh:selected)),0.01,"Official Core wrist attachment")
                    if !left,gesture == .think,(30...114).contains(frame) {
                        let finger=try topology.point(PuppetMotion.thinkingFinger,mesh:selected)
                        let chin=try topology.point(SIMD2(300,268),mesh:XCTUnwrap(byID["face"]))
                        XCTAssertLessThan(distance(finger,chin),1.75,"Actual MOC fingertip/chin contact")
                    }
                    if !left,gesture == .encourage,(30...114).contains(frame) {
                        let axis = w-e,unit = axis/distance(w,e),normal = SIMD2(unit.y,-unit.x)
                        let center = try topology.point(w+unit*22,mesh:selected)
                        let thumb = try topology.point(w+unit*22-normal*13,mesh:selected)
                        let face = try topology.point(SIMD2(300,230),mesh:XCTUnwrap(byID["face"]))
                        let towardHead = face-center,radial = thumb-center
                        let facing = (towardHead.x*radial.x+towardHead.y*radial.y)/(distance(face,center)*distance(thumb,center))
                        XCTAssertLessThan(facing,-0.2,"Dorsal raised fist must keep the thumb on its outer radial edge")
                    }
                }
            }
        }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:temp) }
        try Data([77,79,67,51]+[UInt8](repeating:0,count:60)).write(to:temp.appendingPathComponent("bad.moc3"))
        try Data([0]).write(to:temp.appendingPathComponent("texture.png"))
        let json: [String:Any] = ["Version":3,"FileReferences":["Moc":"bad.moc3","Textures":["texture.png"]]]
        let manifest = temp.appendingPathComponent("bad.model3.json")
        try JSONSerialization.data(withJSONObject:json).write(to:manifest)
        XCTAssertThrowsError(try CubismModel(manifest:manifest)) { error in
            XCTAssertTrue(error.localizedDescription.contains("consistency"))
        }
    }
}
