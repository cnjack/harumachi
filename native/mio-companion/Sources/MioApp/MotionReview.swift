import Foundation
import Metal
import MioCore

/// Offline visual review through the production renderer. This entry point
/// never creates CompanionState, a system monitor, a window or a Clef client.
enum MotionReview {
    static func run(at directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let device = MTLCreateSystemDefaultDevice() else { throw MioRenderer.RenderError.unavailable }
        let gestures: [CharacterGesture] = [.idle, .wave, .think, .talk]
        var records: [[String: Any]] = []
        let catalog = try JSONDecoder().decode(CubismRigGeometry.self,from:Data(contentsOf:MioResources.directory("MioCubism").appendingPathComponent("Mio.bindings.json")))
        func capture(_ renderer: MioRenderer, pose: RigPose, group: String, frame: Int,
                     extra: [String: Any] = [:]) throws {
            let name = String(format: "%@/%04d.png", group, frame)
            let url = directory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try renderer.snapshot(to: url, pose: pose)
            let motion = renderer.motion(for: pose)
            var centers: [String: [Float]] = [:]
            for left in [true, false] {
                let side = left ? "left" : "right"
                let shoulder = SIMD2<Float>(left ? 231 : 369, 320)
                let elbow = SIMD2<Float>(left ? 173 : 427, 418)
                let wrist = SIMD2<Float>(left ? 114 : 486, 508)
                let axis = wrist - elbow
                let direction = axis / sqrt(axis.x * axis.x + axis.y * axis.y)
                for (name, p) in [("shoulder", shoulder), ("elbow", elbow),
                                  ("cuff", wrist - direction * 40), ("wrist", wrist)] {
                    let q = motion.armPoint(p, shoulder: shoulder, elbow: elbow, wrist: wrist, left: left)
                    centers[name + "_" + side] = [q.x + 75, q.y]
                }
            }
            var gaps: [String:Float] = [:]
            if let core=renderer.cubism?.model {
                let output=try core.meshes(),byID=Dictionary(uniqueKeysWithValues:output.map { ($0.id,$0) })
                func point(_ id: String,_ p: SIMD2<Float>) throws -> SIMD2<Float> {
                    guard let mesh=byID[id] else { throw CubismModel.Failure(message:"Missing QA mesh \(id)") }
                    return try catalog.point(p,mesh:mesh)
                }
                for left in [true,false] {
                    let side=left ? "left":"right",s=SIMD2<Float>(left ? 231:369,320),e=SIMD2<Float>(left ? 173:427,418),w=SIMD2<Float>(left ? 114:486,508)
                    let axis=w-e,direction=axis/sqrt(axis.x*axis.x+axis.y*axis.y)
                    let hand=output.first { $0.id.hasPrefix("hand_"+side) && $0.opacity>0.001 }!
                    for (name,id,p) in [("shoulder","arm_"+side,s),("elbow","lower_sleeve_"+side,e),("cuff","forearm_"+side,w-direction*40),("wrist","forearm_"+side,w),("sleeve_cuff","lower_sleeve_"+side,w-direction*54)] {
                        let q=try point(id,p);centers[name+"_"+side]=[q.x,q.y]
                    }
                    let pairs=[("elbow",try point("arm_"+side,e),try point("lower_sleeve_"+side,e)),
                               ("wrist",try point("forearm_"+side,w),try catalog.point(w,mesh:hand)),
                               ("cuff",try point("lower_sleeve_"+side,w-direction*54),try point("forearm_"+side,w-direction*54))]
                    for (joint,a,b) in pairs {let delta=a-b;gaps[joint+"_"+side]=sqrt(delta.x*delta.x+delta.y*delta.y)}
                }
            }
            let neck = motion.torsoPoint(motion.neckPoint(SIMD2(300, 278)))
            let waist = motion.torsoPoint(SIMD2(300, 432))
            centers["neck"] = [neck.x + 75, neck.y]
            centers["waist"] = [waist.x + 75, waist.y]
            var record: [String: Any] = ["frame": name, "group": group, "time": pose.time,
                "phase": pose.gestureTime,"attachmentGaps":gaps,"attachmentMeasurement":"actual Cubism Core vertices", "gesture": pose.gesture.rawValue, "centers": centers,
                "look": [pose.lookX, pose.lookY], "rightElbow": motion.rightElbow,
                "rightHand": [motion.rightHand.x, motion.rightHand.y, motion.rightHand.z,
                    motion.rightHand.w, motion.rightFist, motion.rightChin]]
            record.merge(extra) { _, new in new }
            records.append(record)
        }
        for gesture in gestures {
            let isolated = try MioRenderer(device: device)
            for frame in 0..<210 {
                let time = Double(frame) / 30
                try capture(isolated, pose: RigPose(time: time, lookX: Float(sin(time * 0.8)) * 0.65,
                    speaking: gesture == .talk, gesture: gesture), group: "gesture-\(gesture.rawValue)", frame: frame)
            }
        }
        // Interrupted gestures must use selectGesture and its private transition
        // history, rather than reproducing a similar interpolation in a test.
        for from in gestures { for to in gestures {
            let renderer = try MioRenderer(device: device)
            renderer.pose = RigPose(time: 2, speaking: from == .talk, gesture: from)
            renderer.selectGesture(to, revision: 1)
            let phaseOffset = renderer.pose.gestureTime
            for frame in 0...120 {
                let phase = Double(frame) / 30
                let pose = RigPose(time: 2 + phase, speaking: to == .talk, gesture: to, gestureTime: phaseOffset+phase)
                try capture(renderer, pose: pose, group: "switch-\(from.rawValue)-\(to.rawValue)", frame: frame)
            }
        } }
        for clock in [100.0,3600.0] {
            for (from,to) in [(CharacterGesture.think,CharacterGesture.wave),(.wave,.think)] {
                let late = try MioRenderer(device:device)
                late.pose = RigPose(time:clock,gesture:from,gestureTime:2)
                late.selectGesture(to,revision:1)
                for frame in 0...120 {
                    let phase = Double(frame)/30
                    try capture(late,pose:RigPose(time:clock+phase,gesture:to,gestureTime:phase),
                        group:"late-\(Int(clock))-\(from.rawValue)-\(to.rawValue)",frame:frame)
                }
            }
        }
        let renderer = try MioRenderer(device: device)
        // Include the wrap into the next automatic cycle, at the actual 30 FPS.
        for frame in 0...1566 {
            let time = Double(frame) / 30
            try capture(renderer, pose: RigPose(time: time), group: "automatic", frame: frame)
        }
        for (index, gesture) in gestures.enumerated() {
            for (lookIndex, look) in [SIMD2<Float>(-1, -1), SIMD2(-1, 1), SIMD2(0, 0), SIMD2(1, -1), SIMD2(1, 1)].enumerated() {
                let still = try MioRenderer(device:device)
                try capture(still, pose: RigPose(time: 2, lookX: look.x, lookY: look.y,
                    speaking: gesture == .talk, gesture: gesture), group: "look-extremes", frame: index * 5 + lookIndex)
            }
        }
        // Automatic speech can interrupt an active action without selectGesture.
        for start in [2.0, 18.0, 36.0] {
            let speech = try MioRenderer(device:device)
            for frame in 0...120 {
                let time = start + Double(frame) / 30
                try capture(speech, pose: RigPose(time: time, speaking: frame >= 10 && frame < 25),
                    group: "automatic-speech-\(Int(start))", frame: frame)
            }
        }
        let report: [String: Any] = ["frames": records.count,"skin_join_along":-42, "fps": 30, "size": [750, 1000],
            "systemMonitoringStarted": false, "networkRequests": 0, "audioEnabled": false,
            "virtualDisplayCreated": false, "records": records]
        try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
            .write(to: directory.appendingPathComponent("review-frames.json"))
        print("Offline motion review: \(records.count) Metal frames at \(directory.path)")
    }
}
