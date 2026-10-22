import XCTest
@testable import MioCore

final class HeadScaleTests: XCTestCase {
    func testExportedHeadIsUniformlySmallerWithFixedChinAndBody() throws {
        guard FileManager.default.fileExists(atPath:"/Applications/Live2D Cubism 5.3/res/libLive2DCubismCoreJNI.dylib") else { throw XCTSkip("Official Core is installed separately") }
        let directory = ProcessInfo.processInfo.environment["MIO_HEAD_SCALE_FIXTURE"].map { URL(fileURLWithPath:$0) } ?? URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/MioApp/Resources/MioCubism")
        let model = try CubismModel(manifest:directory.appendingPathComponent("Mio.model3.json"))
        let geometry = try JSONDecoder().decode(CubismRigGeometry.self,from:Data(contentsOf:directory.appendingPathComponent("Mio.bindings.json")))
        try model.update([:])
        let meshes = Dictionary(uniqueKeysWithValues:try model.meshes().map { ($0.id,$0) })
        // Test the official exported vertices, not just the authoring helper.
        // These landmarks span both axes; the old oversized model must fail.
        for p: SIMD2<Float> in [SIMD2(230,120),SIMD2(370,120),SIMD2(300,240)] {
            let actual = try geometry.point(p,mesh:XCTUnwrap(meshes["hair_back"]))
            let expected = SIMD2<Float>(375,268)+(p-SIMD2(300,268))*0.8
            XCTAssertEqual(actual.x,expected.x,accuracy:0.03)
            XCTAssertEqual(actual.y,expected.y,accuracy:0.03)
        }
        let chin = try geometry.point(SIMD2(300,268),mesh:XCTUnwrap(meshes["face"]))
        XCTAssertEqual(chin.x,375,accuracy:0.03)
        XCTAssertEqual(chin.y,268,accuracy:0.03)
        let chest = try geometry.point(SIMD2(300,370),mesh:XCTUnwrap(meshes["torso"]))
        XCTAssertEqual(chest.x,375,accuracy:0.03)
        XCTAssertEqual(chest.y,370,accuracy:0.03)
    }
}
