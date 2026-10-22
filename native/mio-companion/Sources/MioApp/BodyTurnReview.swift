import Foundation
import Metal
import MioCore

enum BodyTurnReview {
    static func run(at directory: URL) throws {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        guard let device=MTLCreateSystemDefaultDevice() else { throw MioRenderer.RenderError.unavailable }
        let renderer=try MioRenderer(device:device)
        var samples: [[String:Any]]=[]
        for gesture in [CharacterGesture.idle,.wave,.think,.talk,.encourage] {
            for direction: Float in [-1,0,1] {
                let pose=RigPose(time:2,lookX:direction,speaking:gesture == .talk,gesture:gesture,gestureTime:2)
                let name="\(gesture.rawValue)-\(Int(direction)).png"
                // Fixed-pose inspection must sample the clip directly. A new
                // gesture's first playback frame is still the idle transition.
                let motion = renderer.cubism!.motions.motion(for:pose)
                try renderer.snapshot(to:directory.appendingPathComponent(name),pose:pose,motion:motion)
                samples.append(["file":name,"gesture":gesture.rawValue,"headDirection":direction])
            }
        }
        for yaw: Float in [-10,0,10] {
            renderer.cubism!.reviewParameters=["ParamBodyAngleX":yaw,"ParamAngleX":0,"ParamAngleY":0,"ParamAngleZ":0,"ParamBodyAngleZ":0,
                "ParamEyeBallX":0,"ParamEyeBallY":0,"ParamHairFront":0,"ParamHairBack":0,"ParamHairSideL":0,"ParamHairSideR":0]
            let name="body-only-\(Int(yaw)).png"
            try renderer.snapshot(to:directory.appendingPathComponent(name),pose:RigPose(time:0,gesture:.idle))
            samples.append(["file":name,"bodyYaw":yaw,"headYaw":0])
        }
        try JSONSerialization.data(withJSONObject:["samples":samples,"audioEnabled":false,"networkRequests":0],options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("body-review.json"))
        print("Body turn: \(samples.count) Metal views")
    }
}
