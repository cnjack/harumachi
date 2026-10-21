import Foundation
import Metal
import MioCore

/// Offscreen acceptance: no AppDelegate, system monitor, network or display.
enum CubismReview {
    static func run(at directory: URL) throws {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        guard let device = MTLCreateSystemDefaultDevice() else { throw MioRenderer.RenderError.unavailable }
        let renderer = try MioRenderer(device:device)
        let original = try MioRenderer(device:device,legacy:true)
        guard let core = renderer.cubism?.model else { throw CubismModel.Failure(message:"Review requires official Cubism Core") }
        var checks: [[String:Any]] = []
        for parameter in core.parameters {
            var values: [String:Float] = ["ParamHandOpenL":0,"ParamHandOpenR":0];values[parameter.id]=parameter.minimum
            try core.update(values);let low = try core.meshes()
            values[parameter.id]=parameter.maximum;try core.update(values);let high = try core.meshes()
            var geometry: Float = 0,opacity: Float = 0
            for (a,b) in zip(low,high) {
                geometry = max(geometry,zip(a.positions,b.positions).map { abs($0-$1) }.max() ?? 0)
                opacity = max(opacity,abs(a.opacity-b.opacity))
            }
            print("Parameter \(parameter.id) [\(parameter.minimum),\(parameter.maximum)] geometry=\(geometry) opacity=\(opacity)")
            guard geometry>0.0001 || opacity>0.0001 else { throw CubismModel.Failure(message:"Unbound parameter: \(parameter.id)") }
            checks.append(["id":parameter.id,"maximumVertexDelta":geometry,"maximumOpacityDelta":opacity])
        }
        try renderer.snapshot(to:directory.appendingPathComponent("default.png"),pose:RigPose(time:0,gesture:.idle))
        guard core.parameters.count == 24 else { throw CubismModel.Failure(message:"Expected 24 live parameters") }
        var frameCount = 0
        func verify(_ pose: RigPose,_ motion: PuppetMotion) throws {
            try core.update(CubismParameters.values(pose:pose,motion:motion))
            let meshes = try core.meshes()
            for side in ["left","right"] {
                let hands = meshes.filter { $0.id.hasPrefix("hand_"+side) && $0.opacity>0.001 }
                guard hands.count == 1 else { throw CubismModel.Failure(message:"Hand ghost/missing \(side): \(hands.map { $0.id })") }
            }
            frameCount += 1
        }
        let gestures: [CharacterGesture] = [.idle,.wave,.think,.talk]
        for gesture in gestures {
            let sourcePose = RigPose(time:3,speaking:gesture == .talk,gesture:gesture,gestureTime:3)
            try original.snapshot(to:directory.appendingPathComponent("source-\(gesture.rawValue).png"),pose:sourcePose,motion:PuppetMotion(pose:sourcePose))
            for frame in 0...Int(gesture.duration*30) {
                let t = Double(frame)/30
                let pose = RigPose(time:t,speaking:gesture == .talk,gesture:gesture,gestureTime:t)
                try verify(pose,PuppetMotion(pose:pose))
            }
            for t in [0.0,1.5,3.0,gesture.duration-0.1] {
                let pose = RigPose(time:t,speaking:gesture == .talk,gesture:gesture,gestureTime:t)
                try renderer.snapshot(to:directory.appendingPathComponent("\(gesture.rawValue)-\(t).png"),pose:pose,motion:PuppetMotion(pose:pose))
            }
        }
        for first in gestures { for second in gestures {
            var playback = MotionPlayback()
            var pose = RigPose(time:0,gesture:first)
            _ = playback.sample(pose)
            pose.time = 2;pose.gestureTime = 2;_ = playback.sample(pose)
            _ = playback.select(second,pose:pose)
            for frame in 0...90 {
                pose.time = 2+Double(frame)/30;pose.gestureTime = Double(frame)/30;pose.gesture = second
                try verify(pose,playback.sample(pose))
            }
        } }
        let report: [String:Any] = ["format":"Cubism MOC3","coreVersion":core.coreVersion,"mocVersion":core.mocVersion,"parameters":checks,"drawables":try core.meshes().count,"coreFrames":frameCount,"metalSnapshots":1+gestures.count*5,"parameterEngine":"official Cubism Core","renderer":"Swift Metal indexed drawables","networkRequests":0,"systemMonitoringStarted":false,"audioEnabled":false,"virtualDisplayCreated":false,"visibleWindowAcceptance":false]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("verification.json"))
        print("Cubism Core/Metal: \(checks.count) effective parameters, \(frameCount) verified frames at \(directory.path)")
    }
}
