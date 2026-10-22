import XCTest
@testable import MioCore

final class HeadVolumeTests: XCTestCase {
    private var assets: URL { ProcessInfo.processInfo.environment["MIO_HEAD_FIXTURE"].map { URL(fileURLWithPath:$0) } ?? URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/MioApp/Resources/MioCubism") }
    func testExportedHeadKeepsSkullAndEyeVolume() throws {
        guard FileManager.default.fileExists(atPath:"/Applications/Live2D Cubism 5.3/res/libLive2DCubismCoreJNI.dylib") else { throw XCTSkip("Official Core is installed separately") }
        let model=try CubismModel(manifest:assets.appendingPathComponent("Mio.model3.json"))
        let geometry=try JSONDecoder().decode(CubismRigGeometry.self,from:Data(contentsOf:assets.appendingPathComponent("Mio.bindings.json")))
        func meshes() throws -> [String:CubismModel.Mesh] { Dictionary(uniqueKeysWithValues:try model.meshes().map {($0.id,$0)}) }
        func point(_ x: Float,_ y: Float,_ mesh: CubismModel.Mesh) throws -> SIMD2<Float> { try geometry.point(SIMD2(x,y),mesh:mesh) }
        try model.update([:]);let front=try meshes()
        for name in ["ear_left","ear_right","nose"] { XCTAssertNotNil(front[name],"Occlusion needs independent source parts: \(name)") }
        for yaw: Float in [-30,-20,-10,10,20,30] { for pitch: Float in [-30,0,30] {
            try model.update(["ParamAngleX":yaw,"ParamAngleY":pitch]);let turned=try meshes()
            let skull=try XCTUnwrap(turned["hair_back"]),skullFront=try XCTUnwrap(front["hair_back"])
            let width=try point(382,200,skull).x-point(218,200,skull).x
            let original=try point(382,200,skullFront).x-point(218,200,skullFront).x
            XCTAssertTrue((0.97...1.03).contains(width/original),"The back of the head must not collapse into the turned face")
            for (side,cx) in [("right",Float(277)),("left",Float(323))] {
                let name="eyes_open_"+side,eye=try XCTUnwrap(turned[name]),eyeFront=try XCTUnwrap(front[name])
                let w=try point(cx+9,205,eye).x-point(cx-9,205,eye).x
                let w0=try point(cx+9,205,eyeFront).x-point(cx-9,205,eyeFront).x
                XCTAssertTrue((0.85...1.04).contains(w/w0),"A turn must retain the original rounded eye, not crush its far half: \(side) \(w/w0)")
            }
            if let nose=turned["nose"],let ear=turned[yaw>0 ? "ear_left":"ear_right"] {
                let noseTravel=try point(300,231,nose).x-point(300,231,front["nose"]!).x
                let earTravel=try point(yaw>0 ? 353:247,220,ear).x-point(yaw>0 ? 353:247,220,front[ear.id]!).x
                // Compare depth to the measured skull width: a uniform head
                // resize must preserve the same relative parallax threshold.
                XCTAssertGreaterThan((noseTravel-earTravel)*(yaw>0 ? 1:-1)/original,8.0/164.0,"Nose and ear cannot slide together on one plane")
            }
        } }
    }
}
