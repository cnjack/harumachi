import Foundation
import Metal
import MioCore

/// Isolated deterministic performance sequences through the production player.
/// No system monitors, audio, network or extra display are created.
enum PerformanceReview {
    static func run(at directory: URL) throws {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        guard let device=MTLCreateSystemDefaultDevice() else { throw MioRenderer.RenderError.unavailable }
        let renderer=try MioRenderer(device:device)
        let core=renderer.cubism!.model
        var frames: [[String:Any]]=[]
        let sequence: [(Double,PerformanceCue)] = [
            (0,PerformanceCue(intent:.welcome,mood:.happy,text:"欢迎回来。今天也一起慢慢来吧。")),
            (7,PerformanceCue(intent:.quiet,mood:.neutral)),
            (13,PerformanceCue(intent:.waiting,mood:.thinking)),
            (17,PerformanceCue(intent:.reply,mood:.concerned,text:"我在听，先别着急。我们可以一件一件慢慢来。")),
            (25,PerformanceCue(intent:.quiet,mood:.neutral))]
        let captures: Set<Int>=[0,60,160,420,780,900,1020,1080,1260,1500,1679]
        var mouthActive=0,pauseFrames=0
        for frame in 0..<1680 {
            let t=Double(frame)/60,entry=sequence.last { $0.0<=t }!
            var pose=RigPose(time:t);pose.present(entry.1,elapsed:t-entry.0)
            let motion=renderer.motion(for:pose)
            let values=CubismParameters.values(pose:pose,motion:motion)
            try core.update(values)
            let meshes=try core.meshes()
            for side in ["left","right"] {
                guard meshes.filter({$0.id.hasPrefix("hand_"+side) && $0.opacity>0.001}).count == 1 else { throw CubismModel.Failure(message:"Performance hand ghost") }
            }
            if pose.mouthAmount>0.1 { mouthActive += 1 }
            if pose.speaking && pose.mouthAmount == 0 { pauseFrames += 1 }
            if entry.1.intent == .quiet && (pose.speaking || pose.resolvedGesture != .idle) { throw CubismModel.Failure(message:"Quiet event moved or spoke") }
            if captures.contains(frame) { try renderer.snapshot(to:directory.appendingPathComponent("flow-\(frame).png"),pose:pose,motion:motion) }
            frames.append(["t":t,"intent":entry.1.intent.rawValue,"gesture":pose.resolvedGesture.rawValue,"mood":pose.mood.rawValue,"mouth":pose.mouthAmount,"thought":motion.thoughtOpacity])
        }
        for mood in Mood.allCases { for x in [-1,0,1] { for y in [-1,0,1] {
            let pose=RigPose(time:0,mood:mood,lookX:Float(x),lookY:Float(y),gesture:.idle)
            try renderer.snapshot(to:directory.appendingPathComponent("\(mood.rawValue)-\(x)-\(y).png"),pose:pose)
        } } }
        let masked=try core.meshes().filter { !$0.masks.isEmpty }
        guard masked.count>=4,mouthActive>60,pauseFrames>60 else { throw CubismModel.Failure(message:"Missing expressions, speech beats or authored masks") }
        let manualRenderer=try MioRenderer(device:device)
        let concern=PerformanceCue(intent:.reply,mood:.concerned,text:"我在听，慢慢说。",expression:.init(style:.concerned,intensity:.strong,hand:.rest))
        let joy=PerformanceCue(intent:.reply,mood:.happy,text:"做到了，一起庆祝吧！",expression:.init(style:.joyful,intensity:.strong,hand:.encourage))
        var manualPose=RigPose(time:0,gesture:.wave,gestureTime:2)
        var manualFrames: [[String:Any]]=[]
        for frame in 0..<360 {
            let t=Double(frame)/60
            manualPose.time=t;manualPose.gestureTime=2
            manualPose.present(frame<120 ? concern:joy,elapsed:frame<120 ? t:frame<240 ? t-2:20+t-4)
            let expected: ExpressionStyle=frame<120 ? .concerned:frame<240 ? .joyful:.neutral
            guard manualPose.resolvedGesture == .wave,manualPose.expression?.style == expected else {
                throw CubismModel.Failure(message:"Manual arms froze or replaced the current reply expression")
            }
            let name=[90,210,359].contains(frame) ? "manual-expression-\(expected.rawValue).png":"manual-intermediate.png"
            try manualRenderer.snapshot(to:directory.appendingPathComponent(name),pose:manualPose,motion:PuppetMotion(pose:manualPose))
            manualFrames.append(["t":t,"gesture":manualPose.resolvedGesture.rawValue,"expression":expected.rawValue,"mouth":manualPose.mouthAmount])
        }
        try FileManager.default.removeItem(at:directory.appendingPathComponent("manual-intermediate.png"))
        if let fixture=ProcessInfo.processInfo.environment["MIO_MASK_FIXTURE"] {
            let inverse=try MioRenderer(device:device,manifest:URL(fileURLWithPath:fixture).appendingPathComponent("Mio.model3.json"))
            guard try inverse.cubism!.model.meshes().contains(where:{$0.invertedMask && !$0.masks.isEmpty}) else { throw CubismModel.Failure(message:"Fixture lacks inverse mask") }
            try inverse.snapshot(to:directory.appendingPathComponent("inverse-mask.png"),pose:RigPose(time:0,gesture:.idle))
        }
        let report: [String:Any] = ["frames":frames,"manualFrames":manualFrames,"moods":Mood.allCases.map(\.rawValue),"combinationSnapshots":45,"maskedMeshes":masked.map(\.id),"mouthActiveFrames":mouthActive,"closedMouthSpeechFrames":pauseFrames,"networkRequests":0,"audioEnabled":false,"systemMonitoringStarted":false,"virtualDisplayCreated":false]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("performance.json"))
        print("Performance: \(frames.count) frames; 45 face/expression combinations; \(masked.count) real Core masks")
    }
}
