import XCTest
import ImageIO
import CoreGraphics
@testable import MioCore

final class ArmDeformationTests: XCTestCase {
    private struct Rig: Decodable {
        struct Layer: Decodable {
            let id: String
            let texture: String
            let rect: [Float]
            let joints: [[Float]]?
            let bendSpans: [Float]?
            let group: String
            let jointPiece: String?
        }
        let canvas: [Float]
        let origin: [Float]?
        let layers: [Layer]
    }
    private func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { a.x * b.y - a.y * b.x }

    // Sample the actual opaque sleeve/skin triangles, not the empty sprite rectangle.
    // Bounds alone passed the previous rig even when its shoulder mesh turned inside out.
    func testOpaqueArmTrianglesKeepTheirOrientationAndArea() throws {
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/MioApp/Resources/Mio")
        let rig = try JSONDecoder().decode(Rig.self, from: Data(contentsOf: resources.appendingPathComponent("Mio.rig.json")))
        for arm in rig.layers where arm.group.hasPrefix("arm_") || arm.group.hasPrefix("hand_") {
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(resources.appendingPathComponent(arm.texture) as CFURL, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
            pixels.withUnsafeMutableBytes { buffer in
                let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            let joints = try XCTUnwrap(arm.joints).map { SIMD2<Float>($0[0], $0[1]) }
            let columns = 24, rows = 64
            var points: [SIMD2<Float>] = []
            for y in 0...rows { for x in 0...columns {
                points.append(SIMD2(arm.rect[0] + arm.rect[2] * Float(x) / Float(columns),
                                    arm.rect[1] + arm.rect[3] * Float(y) / Float(rows)))
            } }
            var triangles: [(Int, Int, Int)] = []
            for y in 0..<rows { for x in 0..<columns {
                let a = y * (columns + 1) + x, b = a + 1, c = a + columns + 1, d = c + 1
                for triangle in [(a, b, c), (b, d, c)] {
                    let center = (points[triangle.0] + points[triangle.1] + points[triangle.2]) / 3
                    let px = min(image.width - 1, max(0, Int((center.x - arm.rect[0]) / arm.rect[2] * Float(image.width))))
                    let py = min(image.height - 1, max(0, Int((center.y - arm.rect[1]) / arm.rect[3] * Float(image.height))))
                    if pixels[(py * image.width + px) * 4 + 3] > 192 { triangles.append(triangle) }
                }
            } }
            // The new registered arm rectangle has more transparent margin;
            // wrist-only source pieces cover fewer cells than full sleeves.
            let opaquePixels = stride(from:3,to:pixels.count,by:4).reduce(0) { $0+(pixels[$1]>220 ? 1:0) }
            let expectedSamples = Float(opaquePixels)/Float(image.width*image.height)*Float(columns*rows*2)
            // Each newly separated piece occupies a different fraction of the
            // common texture rectangle. Keep dense sampling of its actual art.
            XCTAssertGreaterThan(triangles.count,max(24,Int(expectedSamples*0.65)))
            let gestures: [CharacterGesture] = [.idle, .wave, .think, .talk, .encourage]
            var sequences = gestures.map { gesture in
                (gesture.rawValue, (0...210).map { PuppetMotion(pose: RigPose(time: Double($0) / 30, gesture: gesture)) })
            }
            var interruptions: [PuppetMotion] = []
            for from in gestures { for to in gestures {
                let previous = PuppetMotion(pose: RigPose(time: 2, gesture: from))
                for frame in 0...12 {
                    let current = PuppetMotion(pose: RigPose(time: 2 + Double(frame) / 30,
                        gesture: to, gestureTime: Double(frame) / 30))
                    interruptions.append(current.blended(from: previous,
                        fraction: PuppetMotion.smooth(0, 0.4, Float(frame) / 30)))
                }
            } }
            sequences.append(("interruptions", interruptions))
            for (name, sequence) in sequences {
                var minimum: Float = .infinity, maximum: Float = 0
                var worstFrame = 0
                var minX: Float = .infinity, minY: Float = .infinity
                var maxX: Float = -.infinity, maxY: Float = -.infinity
                for (frame, motion) in sequence.enumerated() {
                    let deformed = points.map {
                        motion.armPoint($0, shoulder: joints[0], elbow: joints[1], wrist: joints[2], left: arm.group.hasSuffix("_left"),
                            elbowBendSpan: arm.bendSpans?[0] ?? 104, wristBendSpan: arm.bendSpans?[1] ?? 30,
                            upperArm:arm.jointPiece.map { $0 == "upper" },hand:arm.group.hasPrefix("hand_"))
                    }
                    for (a, b, c) in triangles {
                        let ratio = cross(deformed[b] - deformed[a], deformed[c] - deformed[a])
                            / cross(points[b] - points[a], points[c] - points[a])
                        if ratio < minimum { minimum = ratio; worstFrame = frame }
                        maximum = max(maximum, ratio)
                        let center = (deformed[a] + deformed[b] + deformed[c]) / 3
                        minX = min(minX, center.x); maxX = max(maxX, center.x)
                        minY = min(minY, center.y); maxY = max(maxY, center.y)
                    }
                }
                print("Arm mesh \(arm.id) \(name): area ratio \(minimum)...\(maximum), worst frame \(worstFrame); bounds \(minX),\(minY)...\(maxX),\(maxY)")
                XCTAssertGreaterThan(minimum, 0.20, "\(arm.id) \(name) folds or pinches at frame \(worstFrame)")
                XCTAssertLessThan(maximum, 1.85, "\(arm.id) \(name) stretches the sleeve")
                XCTAssertGreaterThan(minX, (rig.origin?[0] ?? 0) + 5)
                XCTAssertLessThan(maxX, (rig.origin?[0] ?? 0) + rig.canvas[0] - 5)
                XCTAssertGreaterThan(minY, 5); XCTAssertLessThan(maxY, rig.canvas[1] - 5)
            }
        }
    }

    func testGesturesHaveDeliberateArmDirections() {
        let shoulder = SIMD2<Float>(369, 320), elbow = SIMD2<Float>(427, 418), wrist = SIMD2<Float>(486, 508)
        func hand(_ motion: PuppetMotion) -> SIMD2<Float> {
            motion.armPoint(wrist, shoulder: shoulder, elbow: elbow, wrist: wrist, left: false)
        }
        for frame in 30...105 {
            let time = Double(frame) / 30
            let wave = PuppetMotion(pose: RigPose(time: time, gesture: .wave))
            XCTAssertLessThan(hand(wave).y, 280, "Wave beside the head")
            XCTAssertGreaterThan(hand(wave).x, 420, "Keep the waving hand outside the face")
            let think = PuppetMotion(pose: RigPose(time: time, gesture: .think))
            XCTAssertTrue((320...390).contains(hand(think).x),"Thinking wrist stays beside and below the chin")
            XCTAssertTrue((300...365).contains(hand(think).y),"The index reaches up to the chin")
        }
    }
}
