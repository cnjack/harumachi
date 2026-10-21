import Foundation
import Metal
import MioCore

enum EmotionReview {
    static func run(at directory: URL) throws {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        guard let device=MTLCreateSystemDefaultDevice() else { throw MioRenderer.RenderError.unavailable }
        var records: [[String:Any]]=[]
        for style in ExpressionStyle.allCases { for intensity in ExpressionIntensity.allCases {
            let renderer=try MioRenderer(device:device)
            let expression=EmotionalExpression(style:style,intensity:intensity)
            var pose=RigPose(time:0,gesture:.idle);pose.expression=expression
            let name=style.rawValue+"-"+intensity.rawValue
            try renderer.snapshot(to:directory.appendingPathComponent(name+".png"),pose:pose)
            var mixer=EmotionPlayback()
            let values=mixer.apply(CubismParameters.values(pose:pose,motion:PuppetMotion(pose:pose)),expression:expression,time:0)
            records.append(["style":style.rawValue,"intensity":intensity.rawValue,"parameters":values])
        } }
        // Real renderer transitions, including interruptions between inward and
        // outward elbow folds and fist/palm changes during the same talk clip.
        let renderer=try MioRenderer(device:device)
        let sequence: [(Double,EmotionalExpression,String)] = [
            (0,.init(style:.neutral,hand:.rest),"嗯，我在听。"),
            (4,.init(style:.warm,hand:.wave),"欢迎回来，今天也一起慢慢来吧。"),
            (10,.init(style:.joyful,intensity:.strong,hand:.explain),"做到了！这份开心，值得好好记下来。"),
            (16,.init(style:.curious,hand:.chin),"我想想，我们可以先从哪一步开始呢？"),
            (22,.init(style:.concerned,hand:.rest),"我在听，不着急，我们一件一件来。"),
            (28,.init(style:.surprised,intensity:.strong,hand:.rest),"咦？真让人意外。后来怎么样了？"),
            (34,.init(style:.determined,intensity:.strong,hand:.encourage),"再试一次吧，我在这里给你加油。"),
            (40,.init(style:.sleepy,hand:.rest),"今天辛苦啦，晚安，做个好梦。"),
            (46,.init(style:.neutral,hand:.rest),"")]
        let frameCount=3000,saveFrames=ProcessInfo.processInfo.environment["MIO_REVIEW_SAVE_FRAMES"] == "1"
        if saveFrames { try FileManager.default.createDirectory(at:directory.appendingPathComponent("frames"),withIntermediateDirectories:true) }
        var transitions: [[String:Any]]=[]
        var parityMixer=EmotionPlayback()
        for frame in 0..<frameCount {
            let t=Double(frame)/60,entry=sequence.last {$0.0<=t}!
            let cue=PerformanceCue(intent:.reply,mood:entry.1.style.mood,text:entry.2,expression:entry.1)
            var pose=RigPose(time:t);cue.apply(to:&pose,elapsed:t-entry.0)
            let path=directory.appendingPathComponent(saveFrames ? String(format:"frames/%04d.png",frame):(frame%60 == 0 ? String(format:"transition-%04d.png",frame):"transient.png"))
            try renderer.snapshot(to:path,pose:pose)
            let meshes=try renderer.cubism!.model.meshes()
            let hands=meshes.filter {$0.id.hasPrefix("hand_") && $0.opacity>0.001}
            for side in ["left","right"] {
                guard hands.filter({$0.id.hasPrefix("hand_"+side)}).count == 1 else { throw CubismModel.Failure(message:"Emotion hand overlap") }
            }
            let base=CubismParameters.values(pose:pose,motion:PuppetMotion(pose:pose))
            let face=parityMixer.apply(base,expression:pose.expression!,time:t,mouthOwned:true)
            transitions.append(["base":base,"face":face,"vad":parityMixer.vad,"expression":try JSONSerialization.jsonObject(with:JSONEncoder().encode(pose.expression!)),"t":t,"style":entry.1.style.rawValue,"hand":entry.1.hand.rawValue,"text":entry.2,"visibleHands":hands.map(\.id),"gesture":pose.resolvedGesture.rawValue,"mouth":pose.mouthAmount])
        }
        try? FileManager.default.removeItem(at:directory.appendingPathComponent("transient.png"))
        try JSONSerialization.data(withJSONObject:["faces":records,"transitions":transitions,"metalFrames":24+frameCount,"audioEnabled":false,"networkRequests":0,"systemMonitoringStarted":false],options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("emotion-review.json"))
        print("Emotion review: 24 face combinations and \(frameCount) real Metal transition frames")
    }
}
