import AppKit
import MioCore

extension AppDelegate {
    /// Exercises the normal app state and views with synthetic user messages.
    /// This mode never starts system monitoring or reads the normal inbox.
    func runDialogueReview(at directory: URL) {
        Task { @MainActor in
            do {
                let samples = [
                    ("persona", "介绍自己吧", "persona."),
                    ("time", "现在几点了？", "time."),
                    ("work", "工作卡住了，有点不知道下一步怎么做", "work."),
                    ("followup", "然后呢？", "follow_work."),
                    ("quiet", "先别说话，我先忙", "quiet."),
                    ("resume", "可以说话了", "resume."),
                    ("celebrate", "项目做完了，好开心", "celebrate.")
                ]
                var results: [[String:Any]] = []
                for (name, message, prefix) in samples {
                    let before = state.dialogueMemory.replyCount
                    state.draft = message; state.send()
                    let deadline = Date().addingTimeInterval(9)
                    while state.dialogueMemory.replyCount == before && Date() < deadline {
                        try await Task.sleep(for:.milliseconds(50))
                    }
                    guard state.dialogueMemory.replyCount == before+1,
                          let id = state.dialogueMemory.recentReplyIDs.last, id.hasPrefix(prefix) else {
                        if let decision = state.lastDecision { try JSONEncoder().encode(decision).write(to:directory.appendingPathComponent("failed-decision.json")) }
                        if let event = state.events.first {
                            let context = state.dialogueMemory.context(for:event,events:state.events,now:Date())
                            try ClefClient(configuration:ClefConfiguration(baseURL:state.baseURL,model:state.model))
                                .requestBody(for:event,context:context).write(to:directory.appendingPathComponent("failed-request.json"))
                        }
                        throw NSError(domain:"MioDialogueReview",code:1,userInfo:[NSLocalizedDescriptionKey:"Missing contextual reply: \(name), source=\(state.source), phrase=\(state.phrase)"])
                    }
                    if name == "quiet" {
                        guard !state.dialogueMemory.shouldConsider(SystemEvent(kind:"companion.checkin",summary:""),now:Date()) else {
                            throw MioRenderer.RenderError.unavailable
                        }
                    }
                    try await Task.sleep(for:.milliseconds(400))
                    try saveOwnWindow(dashboard,to:directory.appendingPathComponent("\(name)-dashboard.png"))
                    try saveOwnWindow(companion,to:directory.appendingPathComponent("\(name)-desktop.png"))
                    results.append(["name":name,"message":message,"replyID":id,"phrase":state.phrase,
                                    "source":state.source,"connection":state.connection,"error":state.error,
                                    "intent":state.performance?.intent.rawValue ?? "missing", "mood":state.performance?.mood.rawValue ?? "missing",
                                    "expression":state.performance?.expression?.style.rawValue ?? "legacy",
                                    "intensity":state.performance?.expression?.intensity.rawValue ?? "legacy",
                                    "hand":state.performance?.expression?.hand.rawValue ?? "legacy",
                                    "quietMinutes":state.dialogueMemory.context(for:SystemEvent(kind:"startup",summary:""),events:[],now:Date()).quietRemainingMinutes])
                }
                let frames = state.renderer?.frameCount ?? 0
                guard frames >= 120, state.monitor == nil, state.events.count == samples.count else { throw MioRenderer.RenderError.unavailable }
                let result: [String:Any] = ["samples":results,"rendererFrames":frames,"authoredLines":SpeechCatalog.authoredLineCount,
                    "systemMonitoringStarted":false,"audioEnabled":false,"virtualDisplayCreated":false,
                    "screenshotMethod":"own view tree and Metal target; no display capture"]
                try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("dialogue-review.json"))
                state.stop(); exit(0)
            } catch {
                fputs("Dialogue review failed: \(error.localizedDescription)\n",stderr)
                state.stop(); exit(1)
            }
        }
    }
}
