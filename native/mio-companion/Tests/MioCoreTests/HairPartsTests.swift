import XCTest
@testable import MioCore

final class HairPartsTests: XCTestCase {
    private var assets: URL {
        if let fixture=ProcessInfo.processInfo.environment["MIO_HAIR_FIXTURE"] { return URL(fileURLWithPath:fixture) }
        return URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/MioApp/Resources/MioCubism")
    }

    func testSideHairHasIndependentSourceParametersAndAttachedRoots() throws {
        guard FileManager.default.fileExists(atPath:"/Applications/Live2D Cubism 5.3/res/libLive2DCubismCoreJNI.dylib") else { throw XCTSkip("Official Core is installed separately") }
        let model=try CubismModel(manifest:assets.appendingPathComponent("Mio.model3.json"))
        let ids=Set(model.parameters.map(\.id))
        XCTAssertTrue(ids.contains("ParamHairSideL"));XCTAssertTrue(ids.contains("ParamHairSideR"))
        guard ids.contains("ParamHairSideL"),ids.contains("ParamHairSideR") else { return }
        let catalog=try JSONDecoder().decode(CubismRigGeometry.self,from:Data(contentsOf:assets.appendingPathComponent("Mio.bindings.json")))
        try model.update([:]);let base=Dictionary(uniqueKeysWithValues:try model.meshes().map {($0.id,$0)})
        for (side,suffix,x) in [("left","L",Float(370)),("right","R",Float(230))] {
            let id="hair_front_"+side,other="hair_front_"+(side == "left" ? "right":"left")
            for value: Float in [-1,1] {
                try model.update(["ParamHairSide"+suffix:value]);let moved=Dictionary(uniqueKeysWithValues:try model.meshes().map {($0.id,$0)})
                let start=try XCTUnwrap(base[id]),end=try XCTUnwrap(moved[id])
                let tip=try catalog.point(SIMD2(x,280),mesh:end)-catalog.point(SIMD2(x,280),mesh:start)
                XCTAssertGreaterThan(abs(tip.x),0.5)
                XCTAssertEqual(base[other]?.positions,moved[other]?.positions,"The other side must remain independent")
                for y: Float in [192,197,202,208] {
                    let root=try catalog.point(SIMD2(x,y),mesh:end)-catalog.point(SIMD2(x,y),mesh:start)
                    XCTAssertLessThan(abs(root.x)+abs(root.y),0.001,"Hidden root must remain attached")
                }
            }
        }
    }
}
