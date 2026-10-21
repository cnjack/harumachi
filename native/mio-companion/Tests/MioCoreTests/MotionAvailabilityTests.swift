import XCTest
@testable import MioCore

final class MotionAvailabilityTests: XCTestCase {
    func testOnlyRetainedActionsAreSelectableAndPackaged() throws {
        let names = Set(["idle", "wave", "think", "talk", "encourage"])
        XCTAssertEqual(Set(CharacterGesture.allCases.map(\.rawValue)), names.union(["automatic"]))
        XCTAssertNil(CharacterGesture(rawValue: "stretch"))
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/MioApp/Resources/MioCubism")
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf:
            resources.appendingPathComponent("Mio.model3.json"))) as? [String: Any])
        let references = try XCTUnwrap(manifest["FileReferences"] as? [String: Any])
        let motions = try XCTUnwrap(references["Motions"] as? [String: Any])
        XCTAssertEqual(Set(motions.keys), names.subtracting(["idle"]).union(["Idle"]))
        let files = try FileManager.default.contentsOfDirectory(atPath: resources.appendingPathComponent("motions").path)
        XCTAssertEqual(Set(files), Set(names.map { $0 + ".motion3.json" }))
    }

    func testFormerOverheadSlotStaysAtRestInBothPlaybackPaths() {
        var player = MotionPlayback()
        for frame in 0...1560 {
            let time = Double(frame) / 30
            let pose = RigPose(time: time)
            let played = player.sample(pose)
            guard (34...41).contains(time) else { continue }
            let direct = PuppetMotion(pose: pose)
            let rest = PuppetMotion(pose: RigPose(time: time, gesture: .idle))
            for motion in [played, direct] {
                XCTAssertEqual(motion.leftShoulder, rest.leftShoulder, accuracy: 0.0001)
                XCTAssertEqual(motion.rightShoulder, rest.rightShoulder, accuracy: 0.0001)
                XCTAssertEqual(motion.leftElbow, rest.leftElbow, accuracy: 0.0001)
                XCTAssertEqual(motion.rightElbow, rest.rightElbow, accuracy: 0.0001)
            }
        }
    }
}
