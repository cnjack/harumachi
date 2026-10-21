import XCTest
import ImageIO
import CoreGraphics
@testable import MioCore

final class ShoulderSilhouetteTests: XCTestCase {
    func testOfficialMocTucksRaisedSleeveRootWithoutMovingElbow() throws {
        guard FileManager.default.fileExists(atPath:"/Applications/Live2D Cubism 5.3/res/libLive2DCubismCoreJNI.dylib") else {
            throw XCTSkip("Separately installed Cubism Core required")
        }
        let resources=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/MioApp/Resources/MioCubism")
        let model=try CubismModel(manifest:resources.appendingPathComponent("Mio.model3.json"))
        let topology=try JSONDecoder().decode(CubismRigGeometry.self,from:Data(contentsOf:resources.appendingPathComponent("Mio.bindings.json")))
        for left in [true,false] {
            let id = left ? "arm_left":"arm_right",parameter = left ? "ParamShoulderL":"ParamShoulderR"
            let source = SIMD2<Float>(left ? 231:369,320)
            try model.update([parameter:0])
            let neutral = try topology.point(source,mesh:XCTUnwrap(model.meshes().first { $0.id == id }))
            for (outward,expected) in [(Float(-0.38),SIMD2<Float>(0,-7)),
                                       (0.65,SIMD2<Float>(0,0)),(1.85,SIMD2<Float>(left ? 12:-12,-20))] {
                try model.update([parameter:left ? outward:-outward])
                let actual = try topology.point(source,mesh:XCTUnwrap(model.meshes().first { $0.id == id }))-neutral
                XCTAssertEqual(actual.x,expected.x,accuracy:0.01,"Exported shoulder inset must preserve the approved wave")
                XCTAssertEqual(actual.y,expected.y,accuracy:0.01,"Exported shoulder must lift with the garment")
            }
        }
        for frame in 30...90 {
            var motion=PuppetMotion(pose:RigPose(time:Double(frame)/30,gesture:.idle))
            motion.leftShoulder = 1.85; motion.rightShoulder = -1.85
            let pose=RigPose(time:Double(frame)/30,gesture:.idle)
            try model.update(CubismParameters.values(pose:pose,motion:motion))
            let meshes=try model.meshes()
            for left in [true,false] {
                let mesh=try XCTUnwrap(meshes.first { $0.id == (left ? "arm_left":"arm_right") })
                let s=SIMD2<Float>(left ? 231:369,320),e=SIMD2<Float>(left ? 173:427,418)
                let a=e-s,length=sqrt(a.x*a.x+a.y*a.y),inside=s-a/length*18
                let root=try topology.point(inside,mesh:mesh),anchor=try topology.point(s,mesh:mesh),elbow=try topology.point(e,mesh:mesh)
                let d=root-anchor,b=elbow-anchor
                XCTAssertLessThan(sqrt(d.x*d.x+d.y*d.y),11,"Hidden cap must tuck inside the armhole in exported MOC")
                XCTAssertEqual(sqrt(b.x*b.x+b.y*b.y),length,accuracy:0.01,"Keep the visible upper-arm bone rigid")
            }
        }
    }
    func testShoulderHasOneMovingCapAndNoFixedLobes() throws {
        let resources = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/MioApp/Resources/Mio")
        let rig = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:resources.appendingPathComponent("Mio.rig.json"))) as? [String:Any])
        let layers = try XCTUnwrap(rig["layers"] as? [[String:Any]])
        for side in ["left","right"] {
            XCTAssertNil(layers.first { $0["id"] as? String == "shoulder_"+side },"Fixed shoulder patches create hanging flaps under raised arms")
            XCTAssertNil(layers.first { $0["id"] as? String == "sleeve_"+side },"Do not draw the same upper sleeve twice across the torso")
        }
        let torso = try XCTUnwrap(layers.first { $0["id"] as? String == "torso" })
        let rect = torso["rect"] as! [Double]
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(resources.appendingPathComponent("torso.png") as CFURL,nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source,0,nil))
        var bytes = [UInt8](repeating:0,count:image.width*image.height*4)
        bytes.withUnsafeMutableBytes { pointer in
            let context = CGContext(data:pointer.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,
                bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        }
        for x in [220.0,380.0] {
            let px = Int((x-rect[0])/rect[2]*Double(image.width))
            let py = Int((320-rect[1])/rect[3]*Double(image.height))
            XCTAssertLessThan(bytes[(py*image.width+px)*4+3],32,"Torso must not retain a static sleeve cap outside the armhole")
        }
    }
}
