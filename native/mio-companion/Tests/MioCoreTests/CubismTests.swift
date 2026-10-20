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
        XCTAssertEqual(ids.count,22)
        for name in ["idle","wave","stretch","think","talk"] {
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
    func testOfficialCoreAndCorruptMoc() throws {
        let core = "/Applications/Live2D Cubism 5.3/res/libLive2DCubismCoreJNI.dylib"
        guard FileManager.default.fileExists(atPath:core) else { throw XCTSkip("Separately installed official Cubism Core required") }
        let model = try CubismModel(manifest:assets.appendingPathComponent("Mio.model3.json"))
        XCTAssertEqual(model.parameters.count,22);XCTAssertEqual(try model.meshes().count,32)
        XCTAssertEqual(model.mocVersion,3)
        for parameter in model.parameters {
            try model.update([parameter.id:parameter.minimum]);let low = try model.meshes()
            try model.update([parameter.id:parameter.maximum]);let high = try model.meshes()
            let changed = zip(low,high).contains { a,b in
                abs(a.opacity-b.opacity)>0.0001 || zip(a.positions,b.positions).contains { abs($0-$1)>0.0001 }
            }
            XCTAssertTrue(changed,"Unbound \(parameter.id)")
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
