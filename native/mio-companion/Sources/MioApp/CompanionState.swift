import AppKit
import SwiftUI
import MioCore

@MainActor final class CompanionState: ObservableObject {
    @Published var performance: PerformanceCue?
    private var performanceDirector = PerformanceDirector()
    @Published var mood: Mood = .neutral
    @Published var expressionOverride: ExpressionStyle?
    @Published var gesture: CharacterGesture = .automatic
    @Published var gestureRevision = 0
    func play(_ value: CharacterGesture) { gesture = value; gestureRevision += 1 }
    @Published var phrase = "我是澪。今天也一起慢慢来吧。"
    @Published var source = "正在连接 Clef"
    @Published var connection = "尚未验证"
    @Published var events: [SystemEvent] = []
    @Published var decisions = 0
    @Published var frames = 0
    @Published var paused = false
    @Published var draft = ""
    @Published var baseURL: String
    @Published var model: String
    @Published var error = ""
    @Published var speakingUntil = Date.distantPast
    @Published var showCompanion = true
    let inbox: URL
    var monitor: SystemMonitor?
    var renderer: MioRenderer?
    var onVisibility: ((Bool) -> Void)?
    private var latestMessageID: UUID?
    private var gate = EventGate()
    private var pending: [SystemEvent] = []
    private var task: Task<Void, Never>?
    private var epoch = 0
    private var retryAfter = Date.distantPast
    private(set) var dialogueMemory = DialogueMemory()
    private(set) var lastDecision: Decision?
    private let defaults = UserDefaults(suiteName: "io.harumachi.MioCompanion.preferences")!

    init(dataDirectory: URL? = nil) {
        let environment = ProcessInfo.processInfo.environment
        let support = dataDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("HarumachiMio")
        inbox = support.appendingPathComponent("Inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        baseURL = environment["MIO_CLEF_BASE_URL"] ?? defaults.string(forKey: "baseURL") ?? "http://127.0.0.1:8098"
        model = environment["MIO_CLEF_MODEL"] ?? defaults.string(forKey: "model") ?? "clef-omni"
        let greeting = SystemEvent(kind:"startup",summary:"")
        phrase = SpeechCatalog.candidates(for:greeting,context:DialogueContext(now:greeting.date)).first?.text ?? phrase
    }
    func start(monitorSystemEvents: Bool = true) {
        if monitorSystemEvents {
            monitor = SystemMonitor(inbox: inbox) { [weak self] in self?.receive($0) }
            monitor?.start()
            receive(SystemEvent(kind:"startup",summary:"澪已来到桌面"))
        } else {
            // Dedicated connection check: no workspace observers, network/power
            // monitors or inbox reader exist in this mode.
            receive(SystemEvent(kind:"message",summary:"你好，澪。这是一条连接验证消息。",
                                metadata:["source":"connection-test"]))
        }
    }
    func receive(_ event: SystemEvent) {
        guard !paused, gate.accepts(event) else { return }
        dialogueMemory.observe(event)
        if event.kind == "message" {
            latestMessageID = event.id
            performance = PerformanceCue(intent:.waiting,mood:.thinking,at:event.date)
        } else if ["sleep","session.inactive","app.active"].contains(event.kind), Date() >= speakingUntil {
            performance = PerformanceCue(intent:.quiet,mood:event.kind == "sleep" ? .sleepy:.neutral,at:event.date)
        }
        events.insert(event, at: 0)
        if events.count > 80 { events.removeLast(events.count - 80) }
        if pending.count >= 12 { pending.removeFirst() }
        pending.append(event)
        drain()
    }
    func drain() {
        guard task == nil, !paused else { return }
        let currentEpoch = epoch
        task = Task { [weak self] in
            guard let self else { return }
            while !self.pending.isEmpty, !Task.isCancelled, self.epoch == currentEpoch {
                let event = self.pending.removeFirst()
                defer {
                    if event.kind == "message", self.latestMessageID == event.id,
                       self.performance?.intent == .waiting {
                        self.performance = PerformanceCue(intent:.quiet,mood:.neutral)
                    }
                }
                guard Date().timeIntervalSince(event.date) < 60 else { continue }
                guard self.dialogueMemory.shouldConsider(event,now:Date()) else { continue }
                self.dialogueMemory.recordUser(event)
                let context = self.dialogueMemory.context(for:event,events:self.events,now:Date())
                guard !SpeechCatalog.candidates(for:event,context:context).isEmpty else { continue }
                var decision: Decision
                if Date() < self.retryAfter {
                    decision = .offline(for:event,context:context)
                } else {
                    do {
                        decision = try await ClefClient(configuration: ClefConfiguration(baseURL: self.baseURL, model: self.model)).decide(event,context:context)
                        self.connection = "已连接 · \(self.model)"; self.error = ""
                    } catch {
                        guard !Task.isCancelled, self.epoch == currentEpoch else { break }
                        decision = .offline(for:event,context:context)
                        self.connection = "离线 · 30 秒后重试"
                        // Do not show server bodies or URLs that could contain credentials.
                        self.error = (error as? ClefError)?.localizedDescription ?? "Clef 服务暂不可达"
                        self.retryAfter = Date().addingTimeInterval(30)
                    }
                }
                guard !Task.isCancelled, self.epoch == currentEpoch, !self.paused,
                      Date().timeIntervalSince(event.date) < 60 else { continue }
                if event.kind == "message", self.latestMessageID != event.id { continue }
                self.decisions += 1; self.source = decision.source
                self.lastDecision = decision
                // A delayed routine response must not overwrite a newer direct
                // message, nor speak after the session became inactive.
                guard self.dialogueMemory.shouldConsider(event,now:Date()),
                      event.kind == "message" || !self.pending.contains(where: { $0.kind == "message" }) else { continue }
                if let line = SpeechCatalog.resolve(decision,event:event,context:context) {
                    self.mood = decision.expression?.style.mood ?? decision.mood
                    self.phrase = line.text
                    self.performance = self.performanceDirector.response(decision,event:event,text:line.text,now:Date())
                    self.speakingUntil = Date().addingTimeInterval(SpeechTimeline(line.text).duration+0.35)
                    self.dialogueMemory.recordReply(line,at:Date(),expression:decision.expression)
                }
            }
            if self.epoch == currentEpoch { self.task = nil }
        }
    }
    func send() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !paused else { return }
        receive(SystemEvent(kind: "message", summary: value, metadata: ["source": "user"]))
        draft = ""
    }
    func togglePause() {
        paused.toggle(); epoch += 1; task?.cancel(); task = nil; pending.removeAll()
        renderer?.isPaused = paused
        if paused { monitor?.stop(); source = "已暂停接收";performance = nil;speakingUntil = .distantPast }
        else { gate = EventGate(); monitor?.start(); retryAfter = .distantPast; source = "等待事件" }
    }
    func reconnect() {
        do {
            _ = try ClefConfiguration(baseURL: baseURL, model: model).endpoint()
            defaults.set(baseURL, forKey: "baseURL"); defaults.set(model, forKey: "model")
            epoch += 1; task?.cancel(); task = nil; pending.removeAll(); retryAfter = .distantPast
            gate = EventGate(); receive(SystemEvent(kind: "startup", summary: "重新连接 Clef"))
        } catch { self.error = "请输入不含账号、密码和查询参数的 HTTP(S) 服务地址" }
    }
    func stop() { epoch += 1; task?.cancel(); task = nil; pending.removeAll(); monitor?.stop() }
}
