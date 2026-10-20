import XCTest
import Foundation

final class FaceProportionsTests: XCTestCase {
    private struct Rig: Decodable {
        struct Layer: Decodable { let id: String; let rect: [Double] }
        let layers: [Layer]
    }
    func testHeadSilhouetteBalancesBodyAndKeepsNeckJoin() throws {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let rig = try JSONDecoder().decode(Rig.self, from: Data(contentsOf:
            package.appendingPathComponent("Sources/MioApp/Resources/Mio/Mio.rig.json")))
        let layers = Dictionary(uniqueKeysWithValues: rig.layers.map { ($0.id, $0.rect) })
        let head = try XCTUnwrap(layers["hair_front"])
        let torso = try XCTUnwrap(layers["torso"])
        let lower = try XCTUnwrap(layers["lower_body"])
        let body = [lower[0], torso[1], lower[2], lower[1] + lower[3] - torso[1]]
        let face = try XCTUnwrap(layers["face"])
        // Bound the full hair silhouette, not only the internal facial features.
        let bodyParts = ["torso", "lower_body", "arm_left", "arm_right"].compactMap { layers[$0] }
        let fullBodyWidth = bodyParts.map { $0[0] + $0[2] }.max()! - bodyParts.map { $0[0] }.min()!
        XCTAssertTrue((0.46...0.50).contains(head[2] / fullBodyWidth), "Head silhouette is too wide relative to the body")
        let standingHeight = body[1] + body[3] - head[1]
        XCTAssertTrue((0.245...0.265).contains(head[3] / standingHeight), "Head occupies too much of the full figure")
        XCTAssertEqual(head, layers["hair_back"], "Front and back hair must share the same layout")
        XCTAssertEqual(face[0] + face[2] / 2, body[0] + body[2] / 2, accuracy: 0.5)
        let neckOverlap = face[1] + face[3] - body[1]
        XCTAssertTrue((16...24).contains(neckOverlap), "Keep the chin attached to the neck")
    }
    func testFaceFeaturesKeepMioReferenceProportions() throws {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let rig = try JSONDecoder().decode(Rig.self, from: Data(contentsOf:
            package.appendingPathComponent("Sources/MioApp/Resources/Mio/Mio.rig.json")))
        let layers = Dictionary(uniqueKeysWithValues: rig.layers.map { ($0.id, $0.rect) })
        let face = try XCTUnwrap(layers["face"])
        let eyes = try XCTUnwrap(layers["eyes_open"])
        let closedEyes = try XCTUnwrap(layers["eyes_closed"])
        let mouth = try XCTUnwrap(layers["mouth_closed"])
        let openMouth = try XCTUnwrap(layers["mouth_open"])
        // Catch the reported oversized eye span and vertically stretched mouth.
        XCTAssertTrue((0.62...0.72).contains(eyes[2] / face[2]), "Eye pair overwhelms the face")
        XCTAssertTrue((0.18...0.23).contains(mouth[2] / face[2]), "Smile is too wide for Mio")
        XCTAssertTrue((2.50...2.70).contains(eyes[2] / eyes[3]), "Preserve open-eye artwork aspect")
        XCTAssertTrue((2.85...3.05).contains(closedEyes[2] / closedEyes[3]), "Preserve closed-eye artwork aspect")
        XCTAssertTrue((1.65...1.85).contains(openMouth[2] / openMouth[3]), "Talking mouth is vertically stretched")
        XCTAssertLessThanOrEqual(openMouth[2], mouth[2] * 0.65)
        XCTAssertLessThanOrEqual(openMouth[3], face[3] * 0.09)
        XCTAssertTrue((0.76...0.82).contains((mouth[1] + mouth[3] / 2 - face[1]) / face[3]), "Keep a natural chin below the mouth")
        XCTAssertGreaterThan(mouth[1] - eyes[1] - eyes[3], face[3] * 0.14, "Give eyes, nose and mouth breathing space")
        for feature in [eyes, closedEyes, mouth, openMouth] {
            XCTAssertEqual(feature[0] + feature[2] / 2, face[0] + face[2] / 2, accuracy: 0.5)
        }
        XCTAssertEqual(eyes[0], closedEyes[0], accuracy: 0.5)
        XCTAssertEqual(eyes[1], closedEyes[1], accuracy: 0.5)
        XCTAssertEqual(mouth[1] + mouth[3] / 2, openMouth[1] + openMouth[3] / 2, accuracy: 0.5)
    }
}
