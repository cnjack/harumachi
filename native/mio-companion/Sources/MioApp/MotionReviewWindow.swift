import AppKit
import MetalKit
import MioCore

/// Isolated visible renderer acceptance/preview. No CompanionState, Inbox,
/// monitor or network client is constructed; capture reads only this view.
@MainActor final class MotionReviewWindow: NSObject, NSApplicationDelegate {
    let directory: URL
    let app: NSApplication
    let window: NSWindow
    let renderer: MioRenderer
    let started = ProcessInfo.processInfo.systemUptime
    var timer: Timer?
    var selected = -1
    var captured: Set<String> = []
    var progress: [[String:Any]] = []
    var poseChecks: [String:Bool] = [:]
    var poseMeasurements: [String:[String:Any]] = [:]
    var sentSpeech = false
    var revision = 100
    let schedule: [(Double,CharacterGesture)] = [(0,.idle),(1,.wave),(9.5,.think),(14.5,.talk),(19,.encourage),(24.5,.automatic),(31,.idle)]
    // Capture the held thinking pose after contact and the cloud's fade.
    let captures: [(Double,String)] = [(0.8,"idle"),(2.6,"wave"),(12.2,"think"),(16.2,"talk"),(21,"encourage"),(30.5,"automatic"),(33,"look-left"),(36,"look-front"),(39,"look-right")]

    init(at directory: URL, persistent: Bool) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        guard let device = MTLCreateSystemDefaultDevice() else { throw MioRenderer.RenderError.unavailable }
        app = NSApplication.shared
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:persistent ? 480 : 450,height:persistent ? 634 : 600),
            styleMask:[.titled,.closable],backing:.buffered,defer:false)
        renderer = try MioRenderer(device:device)
        super.init()
        app.delegate = self
        app.setActivationPolicy(.regular)
        window.title = persistent ? "澪 · 本地动作预览" : "澪 · 动作离线验收"
        window.backgroundColor = NSColor(calibratedRed:0.96,green:0.96,blue:0.94,alpha:1)
        let content = NSView(frame:window.contentLayoutRect)
        let view = MTKView(frame:NSRect(x:0,y:0,width:persistent ? 480 : 450,height:600),device:device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0.96,0.96,0.94,1)
        view.preferredFramesPerSecond = 60
        view.delegate = renderer
        content.addSubview(view)
        if persistent {
            for (index,gesture) in CharacterGesture.allCases.enumerated() {
                let button = NSButton(title:gesture.title,target:self,action:#selector(play(_:)))
                button.frame = NSRect(x:8+index*77,y:604,width:73,height:26)
                button.bezelStyle = .rounded
                button.identifier = NSUserInterfaceItemIdentifier(gesture.rawValue)
                content.addSubview(button)
            }
        }
        window.contentView = content
        window.center();window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps:true)
        if !persistent {
            timer = Timer.scheduledTimer(timeInterval:0.2,target:self,selector:#selector(update),userInfo:nil,repeats:true)
        }
    }
    static func run(at directory: URL,persistent: Bool = false) throws {
        let review = try MotionReviewWindow(at:directory,persistent:persistent)
        withExtendedLifetime(review) { review.app.run() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    @objc func play(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,let gesture = CharacterGesture(rawValue:id) else { return }
        revision += 1
        renderer.selectGesture(gesture,revision:revision)
    }
    @objc func update() {
        let elapsed = ProcessInfo.processInfo.systemUptime-started
        if let index = schedule.indices.last(where:{schedule[$0].0<=elapsed}),index != selected {
            selected = index
            renderer.selectGesture(schedule[index].1,revision:index+1)
        }
        if elapsed>=25.5 && !sentSpeech { renderer.speakingUntil = Date().addingTimeInterval(0.6);sentSpeech = true }
        if elapsed>=31 { renderer.targetLook = SIMD2(elapsed<34 ? -1:elapsed<37 ? 0:1,0) }
        progress.append(["wallTime":elapsed,"frames":renderer.frameCount,"animationTime":renderer.pose.time])
        do {
            for (time,name) in captures where elapsed>=time && !captured.contains(name) {
                let motion = renderer.motion(for:renderer.pose)
                func wrist(_ left: Bool) -> SIMD2<Float> {
                    motion.armPoint(SIMD2(left ? 114 : 486,508),shoulder:SIMD2(left ? 231 : 369,320),
                        elbow:SIMD2(left ? 173 : 427,418),wrist:SIMD2(left ? 114 : 486,508),left:left)
                }
                let hand = HandPresentation(motion:motion,left:false)
                poseMeasurements[name] = ["wallTime":elapsed,"animationTime":renderer.pose.time,
                    "gestureTime":renderer.pose.gestureTime,"hand":hand.variant,
                    "thoughtOpacity":motion.thoughtOpacity,
                    "leftWristY":wrist(true).y,"rightWristY":wrist(false).y]
                if name.hasPrefix("look-") {
                    let values=CubismParameters.values(pose:renderer.pose,motion:motion)
                    let yaw=values["ParamAngleX"]!,roll=values["ParamAngleZ"]!,bodyYaw=values["ParamBodyAngleX"]!
                    poseMeasurements[name]?["lookX"]=renderer.pose.lookX
                    poseMeasurements[name]?["yaw"]=yaw;poseMeasurements[name]?["roll"]=roll
                    poseMeasurements[name]?["bodyYaw"]=bodyYaw
                    let target: Float=name == "look-left" ? -1:name == "look-right" ? 1:0
                    poseChecks[name] = abs(renderer.pose.lookX-target)<0.01 && abs(roll)<2
                        && (target == 0 ? abs(yaw)<11:yaw*target>20)
                        && abs(bodyYaw)<=6.001 && (target == 0 ? abs(bodyYaw)<2.2:bodyYaw*target>4)
                } else if name == "idle" {
                    let left = wrist(true),right = wrist(false)
                    poseChecks[name] = hand.variant == "relaxed" && left.y > 525 && right.y > 525
                        && abs(left.x-231) < 60 && abs(right.x-369) < 60
                } else if name == "wave" { poseChecks[name] = hand.variant == "palm" && wrist(false).y < 300 }
                else if name == "think" {
                    let finger = motion.armPoint(PuppetMotion.thinkingFinger,shoulder:SIMD2(369,320),
                        elbow:SIMD2(427,418),wrist:SIMD2(486,508),left:false)
                    let target = motion.torsoPoint(motion.headPoint(SIMD2(300,268))+SIMD2(1,1))
                    let d = finger-target
                    poseMeasurements[name]?["fingerDistance"] = sqrt(d.x*d.x+d.y*d.y)
                    poseMeasurements[name]?["chinWeight"] = motion.rightChin
                    poseChecks[name] = hand.variant == "chin" && d.x*d.x+d.y*d.y < 9 && motion.thoughtOpacity > 0.25
                } else if name == "talk" { poseChecks[name] = hand.variant == "palm" }
                else if name == "encourage" { poseChecks[name] = hand.variant == "fist" && wrist(false).y < 380 && wrist(false).y > 230 }
                else {
                    poseChecks[name] = renderer.pose.gesture == .automatic && !renderer.pose.speaking
                        && hand.variant == "relaxed" && wrist(true).y > 525 && wrist(false).y > 525
                        && motion.thoughtOpacity == 0
                }
                try renderer.snapshot(to:directory.appendingPathComponent(name+".png"),pose:renderer.pose)
                captured.insert(name)
            }
            if elapsed>=40.5 {
                try saveOwnWindow(window,to:directory.appendingPathComponent("window.png"))
                let report: [String:Any] = ["wallTime":elapsed,"frames":renderer.frameCount,
                    "averageFPS":Double(renderer.frameCount)/elapsed,"captured":captured.sorted(),
                    "progress":progress,"poseChecks":poseChecks,"poseMeasurements":poseMeasurements,
                    "systemMonitoringStarted":false,"networkRequests":0,
                    "audioEnabled":false,"virtualDisplayCreated":false]
                try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
                    .write(to:directory.appendingPathComponent("native-window.json"))
                guard Double(renderer.frameCount)/elapsed>=50,captured.count==captures.count,poseChecks.values.allSatisfy({$0}) else { throw MioRenderer.RenderError.unavailable }
                exit(0)
            }
        } catch { fputs("Motion window acceptance failed: \(error)\n",stderr);exit(1) }
    }
}
