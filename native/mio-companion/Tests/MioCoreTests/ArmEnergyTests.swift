import XCTest
import ImageIO
import CoreGraphics
@testable import MioCore

final class ArmEnergyTests: XCTestCase {
    private func wrist(_ motion: PuppetMotion, left: Bool = false) -> SIMD2<Float> {
        motion.armPoint(SIMD2(left ? 114 : 486,508),shoulder:SIMD2(left ? 231 : 369,320),
            elbow:SIMD2(left ? 173 : 427,418),wrist:SIMD2(left ? 114 : 486,508),left:left)
    }

    func testSleeveAndBareArmKeepTheirAuthoredVolume() throws {
        let resources=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/MioApp/Resources/Mio")
        let rig=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:resources.appendingPathComponent("Mio.rig.json"))) as? [String:Any])
        let layers=try XCTUnwrap(rig["layers"] as? [[String:Any]])
        for side in ["left","right"] {
            for (prefix,fraction,minimum) in [("arm_",0.5,40.0),("lower_sleeve_",0.3,39.0),("forearm_",0.8,16.0)] {
                let layer=try XCTUnwrap(layers.first { $0["id"] as? String == prefix+side })
                let rect=layer["rect"] as! [Double],joints=layer["joints"] as! [[Double]]
                let a=joints[prefix == "arm_" ? 0:1],b=joints[prefix == "arm_" ? 1:2]
                let length=hypot(b[0]-a[0],b[1]-a[1]),dx=(b[0]-a[0])/length,dy=(b[1]-a[1])/length
                let source=try XCTUnwrap(CGImageSourceCreateWithURL(resources.appendingPathComponent(layer["texture"] as! String) as CFURL,nil))
                let image=try XCTUnwrap(CGImageSourceCreateImageAtIndex(source,0,nil))
                var pixels=[UInt8](repeating:0,count:image.width*image.height*4)
                pixels.withUnsafeMutableBytes { p in
                    let context=CGContext(data:p.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,
                        bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
                    context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
                }
                var occupied:[Double]=[]
                for sample in -320...320 {
                    let across=Double(sample)/4
                    let x=a[0]+(b[0]-a[0])*fraction-dy*across,y=a[1]+(b[1]-a[1])*fraction+dx*across
                    let px=Int((x-rect[0])/rect[2]*Double(image.width)),py=Int((y-rect[1])/rect[3]*Double(image.height))
                    if px>=0 && py>=0 && px<image.width && py<image.height && pixels[(py*image.width+px)*4+3]>128 { occupied.append(across) }
                }
                let width=try XCTUnwrap(occupied.last)-XCTUnwrap(occupied.first)
                XCTAssertGreaterThanOrEqual(width,minimum,"\(prefix+side): sleeve/skin was squeezed into a narrow strip")
                XCTAssertLessThan(width,58,"Do not inflate the sleeve past the shoulder silhouette")
            }
        }
    }

    func testAuthoredActionsReachTheirReadablePosePromptly() {
        let wave=PuppetMotion(pose:RigPose(time:0.7,gesture:.wave))
        XCTAssertLessThan(wrist(wave).y,290,"Greeting should raise the hand within 0.7 seconds")
        let stretch=PuppetMotion(pose:RigPose(time:1.0,gesture:.stretch))
        XCTAssertLessThan(wrist(stretch).y,200)
        XCTAssertLessThan(wrist(stretch,left:true).y,200)
        let think=PuppetMotion(pose:RigPose(time:0.75,gesture:.think))
        let finger=think.armPoint(PuppetMotion.thinkingFinger,shoulder:SIMD2(369,320),elbow:SIMD2(427,418),wrist:SIMD2(486,508),left:false)
        let chin=think.torsoPoint(think.headPoint(SIMD2(300,268))+SIMD2(1,1))
        XCTAssertLessThan(hypot(finger.x-chin.x,finger.y-chin.y),3)
    }

    func testClickedWaveIsResponsiveAtBothDisplayRates() {
        for fps in [30,60] {
            var playback=MotionPlayback()
            let rest=RigPose(time:20,gesture:.idle)
            _=playback.sample(rest);_=playback.select(.wave,pose:rest)
            var reached:Double?
            for frame in 0...fps {
                let elapsed=Double(frame)/Double(fps)
                let motion=playback.sample(RigPose(time:20+elapsed,gesture:.wave,gestureTime:elapsed))
                if wrist(motion).y<290 && reached == nil { reached=elapsed }
            }
            XCTAssertLessThanOrEqual(reached ?? 10,0.8,"Click-to-raised-hand latency at \(fps) FPS")
        }
    }

    func testWaveHasVisibleElbowAndWristFollowThrough() {
        let motions=(30...90).map { PuppetMotion(pose:RigPose(time:Double($0)/30,gesture:.wave)) }
        let elbows=motions.map(\.rightElbow),wrists=motions.map(\.rightWrist)
        XCTAssertGreaterThan(elbows.max()!-elbows.min()!,0.32)
        XCTAssertGreaterThan(wrists.max()!-wrists.min()!,0.32)
    }
}
