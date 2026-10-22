import AppKit
import MioCore

extension AppDelegate {
    /// Uses the same observable state, SwiftUI views and live renderers as the
    /// desktop app. No system observers, external requests or saved preferences.
    func runDesktopExpressionReview(at directory: URL) {
        Task { @MainActor in
            do {
                func renderers(_ view: NSView) -> [MioRenderer] {
                    let own = (view as? TrackingMetalView)?.rigRenderer.map { [$0] } ?? []
                    return own + view.subviews.flatMap(renderers)
                }
                func check(_ condition: Bool,_ message: String) throws {
                    if !condition { throw CubismModel.Failure(message:message) }
                }
                try await Task.sleep(for:.milliseconds(500))
                let players=renderers(dashboard.contentView!)+renderers(companion.contentView!)
                try check(players.count == 2,"Both live character views must exist")
                state.play(.idle)
                state.performance=PerformanceCue(intent:.reply,mood:.neutral,text:"已经说完。",at:Date().addingTimeInterval(-30))
                var samples: [[String:Any]]=[]
                for style in ExpressionStyle.allCases {
                    let before=players.map(\.frameCount)
                    state.expressionOverride=style
                    try await Task.sleep(for:.milliseconds(950))
                    for (i,player) in players.enumerated() {
                        try check(player.frameCount-before[i]>=20,"Live renderer stopped")
                        try check(player.pose.expression?.style == style,"Expression missing from live view")
                        try check(player.pose.speech == nil,"Old reply still owns mouth")
                        try check(player.cubismError == nil,"Cubism update failed")
                        try player.snapshot(to:directory.appendingPathComponent("\(style.rawValue)-character-\(i).png"),pose:player.pose)
                    }
                    try saveOwnWindow(dashboard,to:directory.appendingPathComponent("\(style.rawValue)-dashboard.png"))
                    try saveOwnWindow(companion,to:directory.appendingPathComponent("\(style.rawValue)-desktop.png"))
                    samples.append(["expression":style.rawValue,"frames":players.map(\.frameCount),"bothViewsMatch":true])
                }
                state.play(.wave)
                state.expressionOverride = .joyful
                state.performance=PerformanceCue(intent:.reply,mood:.thinking,text:"让我想想，我们可以一起把这件事情慢慢弄清楚。",expression:.init(style:.curious,hand:.chin))
                try await Task.sleep(for:.milliseconds(700))
                try check(players.allSatisfy {$0.pose.resolvedGesture == .wave && $0.pose.expression?.style == .joyful && $0.pose.speech != nil},"Manual face interrupted speech or arms")
                state.expressionOverride=nil
                try await Task.sleep(for:.milliseconds(500))
                try check(players.allSatisfy {$0.pose.expression?.style == .curious && $0.pose.resolvedGesture == .wave},"Automatic did not restore latest cue")
                try saveOwnWindow(dashboard,to:directory.appendingPathComponent("automatic-dashboard.png"))
                try check(state.monitor == nil && state.events.isEmpty,"Review started system monitoring")
                let report: [String:Any] = ["samples":samples,"bothViewsUseCubism":players.allSatisfy {$0.cubism != nil},"automaticRestoresLatestDecision":true,"manualFaceKeepsSpeechAndArms":true,"systemMonitoringStarted":false,"networkRequests":0,"audioEnabled":false,"virtualDisplayCreated":false]
                try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("desktop-expressions.json"))
                state.stop();exit(0)
            } catch {
                fputs("Desktop expression review failed: \(error)\n",stderr)
                state.stop();exit(1)
            }
        }
    }
}
