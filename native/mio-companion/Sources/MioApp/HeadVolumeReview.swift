import Foundation
import Metal
import MioCore

/// Fixed camera/lighting/pose: volume must be visible without physics or sway.
enum HeadVolumeReview {
    static func run(at directory: URL) throws {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        guard let device=MTLCreateSystemDefaultDevice() else { throw MioRenderer.RenderError.unavailable }
        let runtime=try ProcessInfo.processInfo.environment["MIO_HEAD_FIXTURE"].map { URL(fileURLWithPath:$0) } ?? MioResources.directory("MioCubism")
        let renderer=try MioRenderer(device:device,manifest:runtime.appendingPathComponent("Mio.model3.json"))
        let core=renderer.cubism!.model
        var samples: [[String:Any]]=[]
        for y: Float in [-30,-15,0,15,30] { for x: Float in [-30,-20,-10,0,10,20,30] {
            renderer.cubism!.reviewParameters=["ParamAngleX":x,"ParamAngleY":y,"ParamAngleZ":0,"ParamBodyAngleZ":0,"ParamBodyAngleX":0,
                "ParamEyeBallX":0,"ParamEyeBallY":0,"ParamHairFront":0,"ParamHairBack":0,"ParamHairSideL":0,"ParamHairSideR":0,
                "ParamEyeLOpen":1,"ParamEyeROpen":1,"ParamMouthOpenY":0]
            let name="head-\(Int(x))-\(Int(y)).png"
            try renderer.snapshot(to:directory.appendingPathComponent(name),pose:RigPose(time:0,gesture:.idle))
            let meshes=try core.meshes()
            guard meshes.allSatisfy({$0.positions.allSatisfy(\.isFinite)}) else { throw CubismModel.Failure(message:"Nonfinite head keyform") }
            samples.append(["yaw":x,"pitch":y,"file":name,"drawables":meshes.count])
        } }
        try JSONSerialization.data(withJSONObject:["samples":samples,"metalSnapshots":samples.count,"physicsEnabled":false,"audioEnabled":false,"networkRequests":0],options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("head-review.json"))
        print("Head volume: \(samples.count) fixed-pose Metal views at \(directory.path)")
    }
}
