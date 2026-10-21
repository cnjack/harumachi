import AppKit
import SwiftUI
import Metal
import MioCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var state: CompanionState!
    var dashboard: NSWindow!
    var companion: NSPanel!
    var statusItem: NSStatusItem!
    var smokeDirectory: URL?
    var connectionTestDirectory: URL?
    var dialogueReviewDirectory: URL?
    var smokeGestures: [String] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let at = args.firstIndex(of: "--smoke-test"), at + 1 < args.count {
            smokeDirectory = URL(fileURLWithPath: args[at + 1], isDirectory: true)
            try? FileManager.default.createDirectory(at: smokeDirectory!, withIntermediateDirectories: true)
        }
        if let at = args.firstIndex(of:"--connection-test"), at+1 < args.count {
            connectionTestDirectory = URL(fileURLWithPath:args[at+1],isDirectory:true)
            try? FileManager.default.createDirectory(at:connectionTestDirectory!,withIntermediateDirectories:true)
        }
        if let at = args.firstIndex(of:"--review-dialogue"), at+1 < args.count {
            dialogueReviewDirectory = URL(fileURLWithPath:args[at+1],isDirectory:true)
            try? FileManager.default.createDirectory(at:dialogueReviewDirectory!,withIntermediateDirectories:true)
        }
        state = CompanionState(dataDirectory: (dialogueReviewDirectory ?? connectionTestDirectory ?? smokeDirectory)?.appendingPathComponent("runtime"))
        dashboard = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 972, height: 710), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        dashboard.title = "澪 · 晴町桌面来信"; dashboard.isReleasedWhenClosed = false
        dashboard.contentView = NSHostingView(rootView: Dashboard(state: state))
        dashboard.center(); dashboard.makeKeyAndOrderFront(nil)
        companion = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 338, height: 525), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        companion.isFloatingPanel = true; companion.level = .floating
        companion.isOpaque = false; companion.backgroundColor = .clear; companion.hasShadow = false
        companion.isMovableByWindowBackground = true
        companion.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        companion.contentView = NSHostingView(rootView: DesktopCompanion(state: state) { [weak self] in self?.showDashboard() })
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            companion.setFrameOrigin(NSPoint(x: frame.maxX - 353, y: frame.minY + 15))
        }
        companion.orderFrontRegardless()
        state.onVisibility = { [weak self] visible in
            if visible { self?.companion.orderFrontRegardless() } else { self?.companion.orderOut(nil) }
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "澪"
        let menu = NSMenu()
        menu.addItem(withTitle: "打开桌面来信", action: #selector(showDashboard), keyEquivalent: "")
        menu.addItem(withTitle: "暂停 / 继续接收", action: #selector(togglePause), keyEquivalent: "")
        menu.addItem(withTitle: "角色鼠标穿透", action: #selector(toggleClickThrough), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出澪", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
        if dialogueReviewDirectory == nil { state.start(monitorSystemEvents:connectionTestDirectory == nil) }
        NSApp.activate(ignoringOtherApps: true)
        if let directory = dialogueReviewDirectory { runDialogueReview(at:directory) }
        else if connectionTestDirectory != nil { runConnectionTest() }
        else if smokeDirectory != nil { runSmoke() }
    }
    @objc func showDashboard() { dashboard.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func togglePause() { state.togglePause() }
    @objc func toggleClickThrough(_ sender: NSMenuItem) {
        companion.ignoresMouseEvents.toggle(); sender.state = companion.ignoresMouseEvents ? .on : .off
    }
    @objc func quit() { state.stop(); NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { state?.stop() }
    private func runConnectionTest() {
        guard let directory = connectionTestDirectory else { return }
        DispatchQueue.main.asyncAfter(deadline:.now()+8) { [weak self] in
            guard let self,let renderer = self.state.renderer else { exit(1) }
            do {
                let result: [String:Any] = ["connection":self.state.connection,"decisionSource":self.state.source,
                    "error":self.state.error,"decisions":self.state.decisions,"rendererFrames":renderer.frameCount,
                    "systemMonitoringStarted":self.state.monitor != nil,"eventKinds":self.state.events.map(\.kind),
                    "eventMetadata":self.state.events.map(\.metadata),"audioEnabled":false,"virtualDisplayCreated":false,
                    "screenshotMethod":"own view tree cache plus own Metal render target composition; no display capture API"]
                try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys])
                    .write(to:directory.appendingPathComponent("connection.json"))
                guard self.state.monitor == nil,self.state.events.count == 1,
                      self.state.events[0].kind == "message",self.state.events[0].metadata == ["source":"connection-test"],
                      self.state.source == "Clef 决策",self.state.error.isEmpty,renderer.frameCount >= 120 else {
                    throw MioRenderer.RenderError.unavailable
                }
                try saveOwnWindow(self.dashboard,to:directory.appendingPathComponent("dashboard.png"))
                self.state.stop();exit(0)
            } catch { fputs("Connection window test failed: \(error.localizedDescription)\n",stderr);self.state.stop();exit(1) }
        }
    }
    private func runSmoke() {
        guard let directory = smokeDirectory else { return }
        let preview: [(Double, CharacterGesture)] = [(0.4, .wave), (2.6, .idle), (4.8, .think), (7.0, .talk)]
        for (delay, gesture) in preview {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.state.play(gesture) }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 1.3) { [weak self] in
                guard let self, let renderer = self.state.renderer, renderer.pose.gesture == gesture else { return }
                do {
                    try renderer.snapshot(to: directory.appendingPathComponent("live-\(gesture.rawValue).png"), pose: renderer.pose)
                    try saveOwnWindow(self.dashboard, to: directory.appendingPathComponent("dashboard-\(gesture.rawValue).png"))
                    try saveOwnWindow(self.companion, to: directory.appendingPathComponent("desktop-\(gesture.rawValue).png"))
                    self.smokeGestures.append(gesture.rawValue)
                } catch { fputs("Gesture snapshot failed: \(error)\n", stderr) }
            }
        }
        // All stimulus is confined to this app and its own inbox; no desktop automation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            try? Data("{\"text\":\"收件箱测试：今天也一起加油。\"}".utf8).write(to: self.state.inbox.appendingPathComponent("smoke.json"), options: .atomic)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self else { return }
            do {
                guard let renderer = self.state.renderer else { throw MioRenderer.RenderError.unavailable }
                try renderer.snapshot(to: directory.appendingPathComponent("live-frame.png"), pose: renderer.pose)
                try saveOwnWindow(self.dashboard, to: directory.appendingPathComponent("dashboard.png"))
                try saveOwnWindow(self.companion, to: directory.appendingPathComponent("companion.png"))
                let decisionSource = self.state.source
                let before = self.state.events.count
                self.state.togglePause()
                self.state.receive(SystemEvent(kind: "message", summary: "must be ignored"))
                let pauseWorks = before == self.state.events.count
                self.state.togglePause()
                func renderers(in view: NSView) -> [MioRenderer] {
                    let own = (view as? TrackingMetalView)?.rigRenderer.map { [$0] } ?? []
                    return own + view.subviews.flatMap { renderers(in: $0) }
                }
                let embedded = renderers(in: self.dashboard.contentView!)
                let desktop = renderers(in: self.companion.contentView!)
                let bothUseCubism = embedded.count == 1 && desktop.count == 1
                    && (embedded + desktop).allSatisfy { $0.cubism != nil && $0.frameCount >= 120 }
                let summary: [String: Any] = ["renderedFrames": self.state.frames,
                    "rendererFrames": renderer.frameCount, "pauseBlocksEvents": pauseWorks,
                    "inboxReceived": self.state.events.contains { $0.kind == "message" && $0.metadata["source"] == "inbox" },
                    "eventKinds": Array(Set(self.state.events.map(\.kind))).sorted(),
                    "decisions": self.state.decisions, "connection": self.state.connection,
                    "decisionSource": decisionSource, "mood": self.state.mood.rawValue,
                    "previewedGestures": self.smokeGestures,
                    "availableActions": CharacterGesture.allCases.map(\.rawValue),
                    "dashboardRendererFrames": embedded.map(\.frameCount),
                    "desktopRendererFrames": desktop.map(\.frameCount),
                    "bothViewsUseOfficialCubism": bothUseCubism,
                    "virtualDisplayCreated": false, "audioEnabled": false,
                    "screenshotMethod": "own view tree cache plus own Metal render target composition; no display capture API"]
                try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("smoke.json"))
                guard self.state.frames >= 120, renderer.frameCount >= 120, pauseWorks,
                      bothUseCubism, summary["inboxReceived"] as? Bool == true,
                      Set(self.smokeGestures) == Set(["idle", "wave", "think", "talk"]) else { throw MioRenderer.RenderError.unavailable }
                self.state.stop(); exit(0)
            } catch { fputs("Smoke failed: \(error)\n", stderr); self.state.stop(); exit(1) }
        }
    }
}

@main struct MioMain {
    @MainActor static func main() {
        let args = CommandLine.arguments
        let supported: Set<String> = ["--preview-motion","--review-motion-window","--review-motion","--review-shoulders","--render-samples","--render-motion","--review-cubism","--review-performance","--review-emotion","--review-expression-matrix","--smoke-test","--connection-test","--review-dialogue"]
        if let unknown = args.dropFirst().first(where: { $0.hasPrefix("--") && !supported.contains($0) }) {
            fputs("Unknown Mio argument: \(unknown)\n",stderr);exit(2)
        }
        for flag in supported.subtracting(["--preview-motion"]) {
            if let at = args.firstIndex(of:flag), at+1 >= args.count || args[at+1].hasPrefix("--") {
                fputs("Missing output directory for \(flag)\n",stderr);exit(2)
            }
        }
        if let at = args.firstIndex(of:"--review-expression-matrix"),at+1 < args.count {
            do { try ExpressionStressReview.run(at:URL(fileURLWithPath:args[at+1],isDirectory:true));exit(0) }
            catch { fputs("Expression matrix failed: \(error)\n",stderr);exit(1) }
        }
        if let at = args.firstIndex(of:"--review-emotion"),at+1 < args.count {
            do { try EmotionReview.run(at:URL(fileURLWithPath:args[at+1],isDirectory:true));exit(0) }
            catch { fputs("Emotion review failed: \(error)\n",stderr);exit(1) }
        }
        if let at = args.firstIndex(of:"--review-performance"),at+1 < args.count {
            do { try PerformanceReview.run(at:URL(fileURLWithPath:args[at+1],isDirectory:true));exit(0) }
            catch { fputs("Performance review failed: \(error)\n",stderr);exit(1) }
        }
        if let at = args.firstIndex(of:"--review-cubism"),at+1 < args.count {
            do { try CubismReview.run(at:URL(fileURLWithPath:args[at+1],isDirectory:true));exit(0) }
            catch { fputs("Cubism review failed: \(error)\n",stderr);exit(1) }
        }
        if let at = args.firstIndex(of: "--preview-motion") {
            do {
                let directory = at+1 < args.count ? args[at+1] : "/tmp/mio-motion-preview"
                try MotionReviewWindow.run(at: URL(fileURLWithPath:directory,isDirectory:true),persistent:true)
                exit(0)
            } catch { fputs("Motion preview failed: \(error)\n",stderr);exit(1) }
        }
        if let at = args.firstIndex(of: "--review-motion-window"), at + 1 < args.count {
            do {
                try MotionReviewWindow.run(at: URL(fileURLWithPath: args[at + 1], isDirectory: true))
                exit(0)
            } catch { fputs("Motion window failed: \(error)\n",stderr);exit(1) }
        }
        if let at = args.firstIndex(of: "--review-motion"), at + 1 < args.count {
            do {
                try MotionReview.run(at: URL(fileURLWithPath: args[at + 1], isDirectory: true))
                exit(0)
            } catch { fputs("Motion review failed: \(error)\n", stderr); exit(1) }
        }
        if let at = args.firstIndex(of: "--review-shoulders"), at + 1 < args.count {
            do {
                let directory = URL(fileURLWithPath:args[at+1],isDirectory:true)
                try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
                guard let device = MTLCreateSystemDefaultDevice() else { throw MioRenderer.RenderError.unavailable }
                let renderer = try MioRenderer(device:device)
                for gesture in [CharacterGesture.idle,.wave,.think,.talk,.encourage] {
                    for time in [0.0,0.3,0.6,1.0,2.0,3.0] {
                        let pose = RigPose(time:time,speaking:gesture == .talk,gesture:gesture,gestureTime:time)
                        try renderer.snapshot(to:directory.appendingPathComponent("\(gesture.rawValue)-\(time).png"),
                            pose:pose,motion:PuppetMotion(pose:pose))
                    }
                }
                exit(0)
            } catch { fputs("Shoulder review failed: \(error)\n",stderr);exit(1) }
        }
        if let at = args.firstIndex(of: "--render-samples"), at + 1 < args.count {
            do {
                let dir = URL(fileURLWithPath: args[at + 1], isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                guard let device = MTLCreateSystemDefaultDevice() else { throw MioRenderer.RenderError.unavailable }
                let renderer = try MioRenderer(device: device)
                for (i, mood) in Mood.allCases.enumerated() {
                    try renderer.snapshot(to: dir.appendingPathComponent(mood.rawValue + ".png"), pose: RigPose(time: Double(i) + 0.3, mood: mood, lookX: Float(i - 2) / 2, speaking: mood == .happy))
                }
                try renderer.snapshot(to: dir.appendingPathComponent("blink.png"), pose: RigPose(time: 4.25))
                print("Metal snapshots: \(dir.path)"); exit(0)
            } catch { fputs("Render failed: \(error)\n", stderr); exit(1) }
        }
        if let at = args.firstIndex(of: "--render-motion"), at + 1 < args.count {
            do {
                let dir = URL(fileURLWithPath: args[at + 1], isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                guard let device = MTLCreateSystemDefaultDevice() else { throw MioRenderer.RenderError.unavailable }
                let renderer = try MioRenderer(device: device)
                let gestures: [CharacterGesture] = [.idle, .wave, .think, .talk, .encourage]
                var probes: [[String: Any]] = []
                for (index, gesture) in gestures.enumerated() {
                    for frame in 0..<210 {
                        let t = Double(frame) / 30
                        let pose = RigPose(time: t, lookX: Float(sin(t * 0.8)) * 0.65, speaking: gesture == .talk,
                                           gesture: gesture, gestureTime: t)
                        let name = String(format: "%04d.png", index * 210 + frame)
                        try renderer.snapshot(to: dir.appendingPathComponent(name), pose: pose)
                        let motion = renderer.motion(for: pose)
                        var points: [[Float]] = []
                        // Actual attachment centres: shoulder, cuff and waist.
                        for left in [true, false] {
                            let shoulder = SIMD2<Float>(left ? 231 : 369,320)
                            let elbow = SIMD2<Float>(left ? 173 : 427,418)
                            let wrist = SIMD2<Float>(left ? 114 : 486,508)
                            let axis = wrist-elbow
                            let direction = axis / sqrt(axis.x*axis.x+axis.y*axis.y)
                            for p in [shoulder, wrist-direction*40] {
                                let q = motion.armPoint(p,shoulder:shoulder,elbow:elbow,wrist:wrist,left:left)
                                points.append([q.x+75,q.y])
                            }
                        }
                        for x in [Float(268),300,332] {
                            let q = motion.torsoPoint(SIMD2(x,432))
                            points.append([q.x+75,q.y])
                        }
                        // Probe the painted split elbow and both sides of its
                        // overlap, beyond the old shoulder/cuff-only checks.
                        let elbow = motion.armPoint(SIMD2(427,418),shoulder:SIMD2(369,320),
                            elbow:SIMD2(427,418),wrist:SIMD2(486,508),left:false)
                        for offset in [SIMD2<Float>(0,0),SIMD2(-8,0),SIMD2(8,0),SIMD2(0,-8),SIMD2(0,8)] {
                            let q = elbow+offset
                            points.append([q.x+75,q.y])
                        }
                        // Inspect the actual chin/neck join after source head scaling.
                        for p in [SIMD2<Float>(294,268),SIMD2(306,268),SIMD2(300,288)] {
                            let q = motion.torsoPoint(motion.neckPoint(p))
                            points.append([q.x+75,q.y])
                        }
                        probes.append(["frame":name,"gesture":gesture.rawValue,"attachments":points])
                    }
                }
                let data = try JSONSerialization.data(withJSONObject:probes,options:[.sortedKeys])
                try data.write(to:dir.deletingLastPathComponent().appendingPathComponent("attachment-probes.json"))
                print("Motion frames: 1050 at 30 FPS"); exit(0)
            } catch { fputs("Motion render failed: \(error)\n", stderr); exit(1) }
        }
        if args.contains("--probe-clef") {
            let env = ProcessInfo.processInfo.environment
            let config = ClefConfiguration(baseURL: env["MIO_CLEF_BASE_URL"] ?? "http://127.0.0.1:8098", model: env["MIO_CLEF_MODEL"] ?? "clef-omni", timeout: Double(env["MIO_CLEF_TIMEOUT"] ?? "6") ?? 6)
            Task {
                do {
                    let result = try await ClefClient(configuration: config).decide(SystemEvent(kind: "message", summary: env["MIO_PROBE_TEXT"] ?? "你好，澪。"))
                    print(String(data: try JSONEncoder().encode(result), encoding: .utf8)!); exit(0)
                } catch { fputs("Clef probe failed: \(error.localizedDescription)\n", stderr); exit(2) }
            }
            RunLoop.main.run(); return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
