import XCTest
@testable import MioCore

final class SkirtWidthTests: XCTestCase {
    func testExportedSkirtIsNarrowerWithWaistAndLegsFixed() throws {
        guard FileManager.default.fileExists(atPath:"/Applications/Live2D Cubism 5.3/res/libLive2DCubismCoreJNI.dylib") else { throw XCTSkip("Official Core is installed separately") }
        let directory = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/MioApp/Resources/MioCubism")
        let model = try CubismModel(manifest:directory.appendingPathComponent("Mio.model3.json"))
        let geometry = try JSONDecoder().decode(CubismRigGeometry.self,from:Data(contentsOf:directory.appendingPathComponent("Mio.bindings.json")))
        for yaw: Float in [-10,0,10] {
            try model.update(["ParamBodyAngleX":yaw])
            let mesh = try XCTUnwrap(model.meshes().first { $0.id == "lower_body" })
            // Sample an actual mesh row at the widest visible hem. The old
            // export measures 290 here and must fail this 6% width regression.
            let left = try geometry.point(SIMD2(155,662.625),mesh:mesh)
            let right = try geometry.point(SIMD2(445,662.625),mesh:mesh)
            XCTAssertEqual(right.x-left.x,272.6,accuracy:0.1)
            XCTAssertEqual((left.x+right.x)/2,375,accuracy:0.03)
            XCTAssertEqual(left.y,662.625,accuracy:0.03)
            for p: SIMD2<Float> in [SIMD2(260,434.5),SIMD2(340,434.5),SIMD2(275,700),SIMD2(325,800),SIMD2(260,940),SIMD2(340,940)] {
                let actual = try geometry.point(p,mesh:mesh)
                let expected = BodyRig.turn(p,yaw:yaw)+SIMD2(75,0)
                XCTAssertEqual(actual.x,expected.x,accuracy:0.1)
                XCTAssertEqual(actual.y,expected.y,accuracy:0.03)
            }
        }
    }
}
