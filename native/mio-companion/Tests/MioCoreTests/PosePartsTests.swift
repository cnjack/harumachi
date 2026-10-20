import XCTest
import ImageIO
import CoreGraphics
@testable import MioCore

final class PosePartsTests: XCTestCase {
    func testPaintedWristContoursMatchTheCommonForearm() throws {
        let resources = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/MioApp/Resources/Mio")
        let rig = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:resources.appendingPathComponent("Mio.rig.json"))) as? [String:Any])
        let layers = try XCTUnwrap(rig["layers"] as? [[String:Any]])
        func contour(_ layer: [String:Any],left: Bool) throws -> SIMD2<Double> {
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(resources.appendingPathComponent(layer["texture"] as! String) as CFURL,nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source,0,nil))
            let rect = layer["rect"] as! [Double]
            var bytes = [UInt8](repeating:0,count:image.width*image.height*4)
            bytes.withUnsafeMutableBytes { p in
                let context = CGContext(data:p.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,
                    bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
            }
            let wrist = SIMD2<Double>(left ? 114 : 486,508),axis = SIMD2<Double>(left ? -59 : 59,90)
            let d = axis/sqrt(axis.x*axis.x+axis.y*axis.y),n = SIMD2(-d.y,d.x)
            var positions: [Double] = []
            for step in -160...160 {
                let across = Double(step)/4,p = wrist+n*across
                let x = Int((p.x-rect[0])/rect[2]*Double(image.width)),y = Int((p.y-rect[1])/rect[3]*Double(image.height))
                if x>=0 && y>=0 && x<image.width && y<image.height && bytes[(y*image.width+x)*4+3]>=128 { positions.append(across) }
            }
            return SIMD2(try XCTUnwrap(positions.first),try XCTUnwrap(positions.last))
        }
        for left in [true,false] {
            let side = left ? "left" : "right"
            let forearm = try XCTUnwrap(layers.first { $0["id"] as? String == "forearm_\(side)" })
            let expected = try contour(forearm,left:left)
            for hand in layers where hand["group"] as? String == "hand_\(side)" {
                let actual = try contour(hand,left:left)
                XCTAssertEqual(actual.x,expected.x,accuracy:0.75,"\(hand["id"]!): one wrist edge detaches")
                XCTAssertEqual(actual.y,expected.y,accuracy:0.75,"\(hand["id"]!): one wrist edge overhangs")
            }
        }
    }
    func testPresentedHandsPointActualThumbsTowardHeadThroughGestures() throws {
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/MioApp/Resources/Mio")
        let rig = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf:
            resources.appendingPathComponent("Mio.rig.json"))) as? [String: Any])
        let layers = try XCTUnwrap(rig["layers"] as? [[String: Any]])
        // Locate the thumb from actual alpha, independently of atlas labels.
        var thumbSigns: [String: Float] = [:]
        for layer in layers where ["palm", "back", "inward"].contains(layer["variant"] as? String ?? "") {
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
            let inward = layer["variant"] as? String == "inward"
            let alongBand = inward ? 24...36 : 20...36
            let acrossBand = inward ? 12...18 : 20...32
            var coverages: [Double] = []
            for sign in [-1.0,1.0] {
                var alpha = 0.0
                for along in alongBand { for across in acrossBand {
                    let p = wrist+d*Double(along)+side*(sign*Double(across))
                    let x = Int((p.x-rect[0])/rect[2]*Double(image.width))
                    let y = Int((p.y-rect[1])/rect[3]*Double(image.height))
                    alpha += Double(pixels[(y*image.width+x)*4+3])
                } }
                coverages.append(alpha / Double(alongBand.count*acrossBand.count))
            }
            XCTAssertGreaterThan(abs(coverages[0]-coverages[1]),35,"Thumb must be distinguishable from the little-finger edge")
            thumbSigns[layer["id"] as! String] = coverages[0] > coverages[1] ? -1 : 1
        }
        for (gesture,left) in [(CharacterGesture.wave,false),(.talk,false)] {
            let shoulder = SIMD2<Float>(left ? 231 : 369,320)
            let elbow = SIMD2<Float>(left ? 173 : 427,418), wrist = SIMD2<Float>(left ? 114 : 486,508)
            let axis = wrist-elbow, d = axis/sqrt(axis.x*axis.x+axis.y*axis.y)
            let side = SIMD2(d.y,-d.x), centre = wrist+d*28
            let prefix = left ? "hand_left_" : "hand_right_"
            var minimumFacing: Float = 1
            var samples = 0
            for frame in 0...210 {
                let pose = RigPose(time:Double(frame)/30,gesture:gesture)
                let motion = PuppetMotion(pose:pose), weights = left ? motion.leftHand : motion.rightHand
                guard weights.y+weights.z+weights.w > 0.99 else { continue }
                let variant = weights.w > 0.5 ? "inward" : (weights.y > weights.z ? "palm" : "back")
                let sign = try XCTUnwrap(thumbSigns[prefix+variant])
                let palm = motion.armPoint(centre,shoulder:shoulder,elbow:elbow,wrist:wrist,left:left)
                let thumb = motion.armPoint(centre+side*sign*26,shoulder:shoulder,elbow:elbow,wrist:wrist,left:left)
                let towardHead = motion.torsoPoint(motion.headPoint(SIMD2(300,200)))-palm
                let towardThumb = thumb-palm
                let facing = (towardHead.x*towardThumb.x+towardHead.y*towardThumb.y)
                    / sqrt((towardHead.x*towardHead.x+towardHead.y*towardHead.y)
                           * (towardThumb.x*towardThumb.x+towardThumb.y*towardThumb.y))
                minimumFacing = min(minimumFacing,facing); samples += 1
            }
            print("Presented thumb \(gesture) \(prefix): \(samples) phases, minimum head-facing dot \(minimumFacing)")
            XCTAssertGreaterThan(samples,60,"At least two seconds of fully presented palm after the slower lift/return")
            XCTAssertGreaterThan(minimumFacing,0.15,"\(gesture) \(prefix): the presented thumb points away from the head")
        }
    }
    func testStretchUsesCompactFistsBeforeRaisingAndReleasesAfterLowering() throws {
        let resources = URL(fileURLWithPath:#filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/MioApp/Resources/Mio")
        let rig = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:
            resources.appendingPathComponent("Mio.rig.json"))) as? [String:Any])
        let layers = try XCTUnwrap(rig["layers"] as? [[String:Any]])
        for side in ["left","right"] {
            let layer = try XCTUnwrap(layers.first { $0["id"] as? String == "hand_\(side)_fist" },
                "Stretch needs a separately drawn closed hand")
            let rect = layer["rect"] as! [Double], joints = layer["joints"] as! [[Double]]
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(resources.appendingPathComponent(layer["texture"] as! String) as CFURL,nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source,0,nil))
            var pixels = [UInt8](repeating:0,count:image.width*image.height*4)
            pixels.withUnsafeMutableBytes { p in
                let ctx = CGContext(data:p.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,
                    bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
                ctx.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
            }
            let wrist = SIMD2(joints[2][0],joints[2][1]), axis = wrist-SIMD2(joints[1][0],joints[1][1])
            let direction = axis/sqrt(axis.x*axis.x+axis.y*axis.y)
            var reach = 0.0, across = 0.0
            for y in 0..<image.height { for x in 0..<image.width where pixels[(y*image.width+x)*4+3] > 128 {
                let p = SIMD2(rect[0]+(Double(x)+0.5)/Double(image.width)*rect[2],
                              rect[1]+(Double(y)+0.5)/Double(image.height)*rect[3])-wrist
                let along = p.x*direction.x+p.y*direction.y
                if along > 0 {
                    reach = max(reach,along)
                    across = max(across,abs(p.x*direction.y-p.y*direction.x))
                }
            } }
            print("Fist \(side): reach \(reach), half-width \(across)")
            XCTAssertTrue((27...43).contains(reach),"A fist must not retain the open hand's long fingers")
            XCTAssertTrue((13...23).contains(across),"Keep the closed fist proportional to the wrist")
        }
        for time in [0.35,1,2,4,6.65] {
            let motion = PuppetMotion(pose:RigPose(time:time,gesture:.stretch))
            XCTAssertEqual(motion.leftFist,1,accuracy:0.0001)
            XCTAssertEqual(motion.rightFist,1,accuracy:0.0001)
            XCTAssertEqual(motion.leftHand,.zero)
            XCTAssertEqual(motion.rightHand,.zero)
        }
        for time in [0.0,7.0] {
            let motion = PuppetMotion(pose:RigPose(time:time,gesture:.stretch))
            XCTAssertEqual(motion.leftFist,0)
            XCTAssertEqual(motion.rightFist,0)
            XCTAssertEqual(motion.leftHand,SIMD4(1,0,0,0))
            XCTAssertEqual(motion.rightHand,SIMD4(1,0,0,0))
        }
    }
    func testPalmBackAndInwardThumbsHaveCorrectHandednessInActualTextures() throws {
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/MioApp/Resources/Mio")
        let rig = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf:
            resources.appendingPathComponent("Mio.rig.json"))) as? [String: Any])
        let layers = try XCTUnwrap(rig["layers"] as? [[String: Any]])
        for layer in layers where ["palm", "back", "inward"].contains(layer["variant"] as? String ?? "") {
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
            let alongBand = variant == "inward" ? 24...36 : 20...36
            let acrossBand = variant == "inward" ? 12...18 : 20...32
            func coverage(_ sign: Double) -> Double {
                var sum: Double = 0
                for along in alongBand { for across in acrossBand {
                    let p = wrist+d*Double(along)+side*(sign*Double(across))
                    let x = Int((p.x-rect[0])/rect[2]*Double(image.width))
                    let y = Int((p.y-rect[1])/rect[3]*Double(image.height))
                    sum += Double(pixels[(y*image.width+x)*4+3])
                } }
                return sum / Double(alongBand.count*acrossBand.count)
            }
            // With fingers down in rest space, the palm thumb occupies the
            // outer edge; lifting the forearm makes it point toward the head.
            // Back-of-hand and inward side art must occupy the opposite edge. The sampled band
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
            let expected: Set<String> = side == "right" ? ["relaxed","palm","back","inward","fist","chin"] : ["relaxed","palm","back","inward","fist"]
            XCTAssertEqual(Set(hands.compactMap { $0["variant"] as? String }), expected,
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
        XCTAssertEqual(stretch.leftHand,.zero)
        XCTAssertEqual(stretch.rightHand,.zero)
        XCTAssertEqual(stretch.leftFist,1)
        XCTAssertEqual(stretch.rightFist,1)
        XCTAssertEqual(think.rightHand,.zero)
        XCTAssertEqual(think.rightChin,1)
        for gesture in CharacterGesture.allCases {
            for frame in 0...210 {
                let current = PuppetMotion(pose: RigPose(time: Double(frame)/30, gesture: gesture))
                let motion = current.blended(from: wave, fraction: Float(frame)/210)
                for (weights,fist,chin) in [(motion.leftHand,motion.leftFist,Float(0)),(motion.rightHand,motion.rightFist,motion.rightChin)] {
                    XCTAssertEqual(weights.x+weights.y+weights.z+weights.w+fist+chin, 1, accuracy: 0.0001)
                    XCTAssertTrue((0..<4).allSatisfy { weights[$0] >= 0 && weights[$0] <= 1 })
                    XCTAssertTrue((0...1).contains(fist))
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
