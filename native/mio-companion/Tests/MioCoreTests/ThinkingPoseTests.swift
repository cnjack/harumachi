import XCTest
import ImageIO
import CoreGraphics
@testable import MioCore

final class ThinkingPoseTests: XCTestCase {
    func testThinkingFingerTouchesChinWhileHeadTiltsAndLooksAround() {
        // Measured fingertip after source wrist registration; independent of
        // the movement targets, so the old waist-level pose fails this check.
        let finger = SIMD2<Float>(547,554)
        let shoulder = SIMD2<Float>(369,320), elbow = SIMD2<Float>(427,418), wrist = SIMD2<Float>(486,508)
        for look in [Float(-1),0,1] {
            for frame in 30...117 {
                let motion = PuppetMotion(pose:RigPose(time:Double(frame)/30,lookX:look,lookY:look,gesture:.think))
                let actual = motion.armPoint(finger,shoulder:shoulder,elbow:elbow,wrist:wrist,left:false)
                let chin = motion.torsoPoint(motion.headPoint(SIMD2(300,268))+SIMD2(1,1))
                let distance = actual-chin
                XCTAssertLessThan(sqrt(distance.x*distance.x+distance.y*distance.y),2.0,"The fingertip must touch the moving chin, not float by the waist")
                let resting = PuppetMotion(pose:RigPose(time:Double(frame)/30,lookX:look,lookY:look,gesture:.idle))
                XCTAssertGreaterThan(motion.head-resting.head,0.10,"Thinking needs a visible gentle head tilt")
                XCTAssertLessThan(abs(motion.rightShoulder),0.8,"Use the short shoulder turn, not an equivalent full revolution")
            }
        }
    }
    func testThoughtCloudFollowsContactAndFadesWithGesture() {
        for time in [0.0,0.25,0.5,4.3,4.9,5.0] {
            XCTAssertEqual(PuppetMotion(pose:RigPose(time:time,gesture:.think)).thoughtOpacity,0)
        }
        for time in [1.2,2.0,3.8] {
            let motion = PuppetMotion(pose:RigPose(time:time,gesture:.think))
            XCTAssertEqual(motion.thoughtOpacity,1)
            XCTAssertEqual(motion.rightChin,1)
        }
        for gesture in [CharacterGesture.idle,.wave,.stretch,.talk] {
            XCTAssertEqual(PuppetMotion(pose:RigPose(time:2,gesture:gesture)).thoughtOpacity,0)
        }
    }
    func testThinkingHasDedicatedIndexHandAndCloudSourceLayers() throws {
        let resources = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/MioApp/Resources/Mio")
        let rig = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:resources.appendingPathComponent("Mio.rig.json"))) as? [String:Any])
        let layers = try XCTUnwrap(rig["layers"] as? [[String:Any]])
        for id in ["hand_right_chin","hand_right_chin_front","thought_cloud"] {
            let layer = try XCTUnwrap(layers.first { $0["id"] as? String == id },"Thinking needs its own \(id) source artwork")
            let texture = try XCTUnwrap(layer["texture"] as? String)
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(resources.appendingPathComponent(texture) as CFURL,nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source,0,nil))
            XCTAssertGreaterThan(image.width,100)
            if id == "hand_right_chin_front" {
                let point = try XCTUnwrap(layer["contactPoint"] as? [Float])
                XCTAssertEqual(point,[PuppetMotion.thinkingFinger.x,PuppetMotion.thinkingFinger.y])
                let rect = try XCTUnwrap(layer["rect"] as? [Float])
                var pixels = [UInt8](repeating:0,count:image.width*image.height*4)
                pixels.withUnsafeMutableBytes { buffer in
                    let context = CGContext(data:buffer.baseAddress,width:image.width,height:image.height,
                        bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
                    context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
                }
                let x = Int(((point[0]-rect[0])/rect[2]*Float(image.width)).rounded())
                let y = Int(((point[1]-rect[1])/rect[3]*Float(image.height)).rounded())
                XCTAssertGreaterThan(pixels[(y*image.width+x)*4+3],192,"The contact anchor must be on actual fingertip pixels")
            }
        }
    }
}
