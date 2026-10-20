import XCTest
import ImageIO
import CoreGraphics
@testable import MioCore

final class PosePartsTests: XCTestCase {
    func testPalmAndBackThumbsHaveCorrectHandednessInActualTextures() throws {
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/MioApp/Resources/Mio")
        let rig = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf:
            resources.appendingPathComponent("Mio.rig.json"))) as? [String: Any])
        let layers = try XCTUnwrap(rig["layers"] as? [[String: Any]])
        for layer in layers where ["palm", "back"].contains(layer["variant"] as? String ?? "") {
            let id = layer["id"] as! String, variant = layer["variant"] as! String
            let left = layer["group"] as! String == "hand_left" // screen side
            let rect = layer["rect"] as! [Double], joints = layer["joints"] as! [[Double]]
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(resources.appendingPathComponent(layer["texture"] as! String) as CFURL,nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source,0,nil))
            var pixels = [UInt8](repeating:0,count:image.width*image.height*4)
            pixels.withUnsafeMutableBytes { p in
                let context = CGContext(data:p.baseAddress,width:image.width,height:image.height,
                    bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
            }
            let wrist = SIMD2(joints[2][0],joints[2][1]), axis = wrist-SIMD2(joints[1][0],joints[1][1])
            let d = axis / sqrt(axis.x*axis.x+axis.y*axis.y), side = SIMD2(d.y,-d.x)
            func coverage(_ sign: Double) -> Double {
                var sum: Double = 0
                for along in 20...36 { for across in 20...32 {
                    let p = wrist+d*Double(along)+side*(sign*Double(across))
                    let x = Int((p.x-rect[0])/rect[2]*Double(image.width))
                    let y = Int((p.y-rect[1])/rect[3]*Double(image.height))
                    sum += Double(pixels[(y*image.width+x)*4+3])
                } }
                return sum / (17*13)
            }
            // With fingers down in rest space, the palm thumb occupies the
            // outer edge; lifting the forearm makes it point toward the head.
            // Back-of-hand art must occupy the opposite edge. The sampled band
            // is beyond the palm edge and above the long fingertips.
            let expected: Double = (left ? -1 : 1) * (variant == "palm" ? 1 : -1)
            let correct = coverage(expected), wrong = coverage(-expected)
            print("Thumb pixels \(id): correct \(correct), opposite \(wrong)")
            XCTAssertGreaterThan(correct, 50, "\(id): missing thumb on the anatomical side")
            XCTAssertGreaterThan(correct-wrong, 35, "\(id): mirrored hand attached to the wrong arm")
        }
    }
    func testSourceIncludesHandsAndOverlappingBodyJoints() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Sources/MioApp/Resources/Mio/Mio.rig.json"))
        let rig = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let layers = try XCTUnwrap(rig["layers"] as? [[String: Any]])
        for side in ["left", "right"] {
            let hands = layers.filter { $0["group"] as? String == "hand_\(side)" }
            XCTAssertEqual(Set(hands.compactMap { $0["variant"] as? String }), ["relaxed", "palm", "back", "inward"],
                "Rotating one hand texture cannot turn its palm toward the viewer")
            XCTAssertNotNil(layers.first { $0["id"] as? String == "shoulder_\(side)" },
                "The shoulder needs drawn underarm coverage")
        }
        let upper = layers.first { $0["group"] as? String == "torso" }
        let lower = layers.first { $0["group"] as? String == "lower_body" }
        XCTAssertNotNil(upper, "Upper body must be separate from the skirt")
        XCTAssertNotNil(lower, "Skirt needs a painted hidden waist extension")
        if let a = upper?["rect"] as? [Double], let b = lower?["rect"] as? [Double] {
            XCTAssertGreaterThan(a[1] + a[3] - b[1], 70, "Waist and cardigan need real overlap for bending")
        }
    }
    func testHandChoicesAndTransitionsKeepFullCoverage() {
        let wave = PuppetMotion(pose: RigPose(time: 2, gesture: .wave))
        let stretch = PuppetMotion(pose: RigPose(time: 2, gesture: .stretch))
        let think = PuppetMotion(pose: RigPose(time: 2, gesture: .think))
        XCTAssertEqual(wave.rightHand, SIMD4(0,1,0,0))
        XCTAssertEqual(stretch.leftHand, SIMD4(0,0,1,0))
        XCTAssertEqual(think.rightHand, SIMD4(0,0,0,1))
        for gesture in CharacterGesture.allCases {
            for frame in 0...210 {
                let current = PuppetMotion(pose: RigPose(time: Double(frame)/30, gesture: gesture))
                let motion = current.blended(from: wave, fraction: Float(frame)/210)
                for weights in [motion.leftHand, motion.rightHand] {
                    XCTAssertEqual(weights.x+weights.y+weights.z+weights.w, 1, accuracy: 0.0001)
                    XCTAssertTrue((0..<4).allSatisfy { weights[$0] >= 0 && weights[$0] <= 1 })
                }
            }
        }
        for frame in 0...210 {
            let motion = PuppetMotion(pose: RigPose(time: Double(frame)/30, gesture: .stretch))
            let waist = SIMD2<Float>(300,432), foot = SIMD2<Float>(350,980)
            XCTAssertEqual(motion.lowerBodyPoint(waist), motion.torsoPoint(waist))
            XCTAssertEqual(motion.lowerBodyPoint(foot), foot)
        }
    }
}
