import Foundation

public enum DayPeriod: String, Codable, CaseIterable, Sendable {
    case dawn, morning, noon, afternoon, evening, night
    public init(hour: Int) {
        switch hour {
        case 5..<8: self = .dawn
        case 8..<11: self = .morning
        case 11..<14: self = .noon
        case 14..<18: self = .afternoon
        case 18..<22: self = .evening
        default: self = .night
        }
    }
}

public struct DialogueTurn: Codable, Sendable {
    public let role: String
    public let text: String
    public let date: Date
    public let replyID: String?
    public let eventID: UUID?
    public let expression: EmotionalExpression?
    public init(role: String, text: String, date: Date, replyID: String? = nil, eventID: UUID? = nil, expression: EmotionalExpression? = nil) {
        self.role = role; self.text = String(text.prefix(300)); self.date = date
        self.replyID = replyID; self.eventID = eventID;self.expression=expression
    }
}

public struct ContextEvent: Codable, Sendable {
    public let kind: String
    public let secondsAgo: Int
    public let metadata: [String: String]
}

public struct DialogueContext: Codable, Sendable {
    public static let persona = """
    你是澪（Mio），来自晴町、负责社区活动联络的年轻成年姑娘，现在作为桌面角色陪伴用户。
    说中文，温柔、细心、略带俏皮，偶尔聊公告栏、河边长椅、集市和夏祭；不要句句重复自我介绍。
    尊重用户自己的生活与节奏，不说教、不催促，不假装看见屏幕或知道用户未告诉你的事情。
    晴町是角色的故事背景，不把虚构回忆说成与用户真实发生过的经历。
    结合当地时间、上一轮对话和已经说过的内容，选择贴切、简短且不重复的一句。
    """
    public let localDate: String
    public let localTime: String
    public let weekday: String
    public let timeZone: String
    public let period: DayPeriod
    public let weekend: Bool
    public let sessionMinutes: Int
    public let conversation: [DialogueTurn]
    public let recentEvents: [ContextEvent]
    public let recentReplyIDs: [String]
    public let replyCount: Int
    public let quietRemainingMinutes: Int

    public init(now: Date = Date(), calendar: Calendar = .current, sessionStarted: Date? = nil,
                conversation: [DialogueTurn] = [], events: [SystemEvent] = [],
                recentReplyIDs: [String] = [], replyCount: Int = 0,
                quietUntil: Date = .distantPast, excludingEvent: UUID? = nil) {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: now)
        localDate = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 1, c.day ?? 1)
        localTime = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        weekday = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"][(c.weekday ?? 1)-1]
        timeZone = calendar.timeZone.identifier
        period = DayPeriod(hour: c.hour ?? 0); weekend = calendar.isDateInWeekend(now)
        sessionMinutes = min(1440, max(0, Int(now.timeIntervalSince(sessionStarted ?? now)/60)))
        self.conversation = Array(conversation.filter {
            (0...1800).contains(now.timeIntervalSince($0.date)) && (excludingEvent == nil || $0.eventID != excludingEvent)
        }.suffix(8))
        recentEvents = events.filter {
            (0...600).contains(now.timeIntervalSince($0.date)) && $0.id != excludingEvent && $0.kind != "message"
        }.sorted { $0.date > $1.date }.prefix(8).reversed().map {
            ContextEvent(kind: String($0.kind.prefix(40)), secondsAgo: Int(now.timeIntervalSince($0.date)), metadata: $0.contextMetadata)
        }
        self.recentReplyIDs = Array(recentReplyIDs.suffix(20))
        self.replyCount = replyCount
        quietRemainingMinutes = max(0, Int(ceil(quietUntil.timeIntervalSince(now)/60)))
    }
}

extension SystemEvent {
    /// Deliberately submitted messages are the only free text sent to Clef.
    /// Other events expose a small, bounded subset of coarse metadata.
    public var contextMetadata: [String: String] {
        let keys: [String]
        switch kind {
        case "app.active", "app.launch", "app.quit": keys = ["bundle_id"]
        case "network": keys = ["status"]
        case "power": keys = ["source"]
        case "thermal": keys = ["level"]
        case "message": keys = ["source"]
        case "time.period": keys = ["period"]
        default: keys = []
        }
        return Dictionary(uniqueKeysWithValues: keys.compactMap { key in
            metadata[key].map { (key, String($0.prefix(100))) }
        })
    }
}

/// Transient memory belongs to the current app session; never written to disk.
public struct DialogueMemory {
    public private(set) var conversation: [DialogueTurn] = []
    public private(set) var recentReplyIDs: [String] = []
    public private(set) var replyCount = 0
    public private(set) var sessionStarted: Date
    public private(set) var quietUntil = Date.distantPast
    public private(set) var lastSpokenAt = Date.distantPast
    public private(set) var sessionActive = true
    public init(now: Date = Date()) { sessionStarted = now }

    public mutating func observe(_ event: SystemEvent) {
        switch event.kind {
        case "sleep", "session.inactive": sessionActive = false
        case "wake", "session.active":
            if !sessionActive { sessionStarted = event.date }
            sessionActive = true
        default: break
        }
    }
    public mutating func recordUser(_ event: SystemEvent) {
        guard event.kind == "message" else { return }
        conversation.append(DialogueTurn(role: "user", text: event.summary, date: event.date, eventID: event.id))
        conversation = Array(conversation.suffix(12))
        switch SpeechCatalog.topic(event.summary) {
        case "quiet": quietUntil = event.date.addingTimeInterval(20*60)
        case "resume": quietUntil = .distantPast
        default: break
        }
    }
    public mutating func recordReply(_ line: DialogueLine, at now: Date, expression: EmotionalExpression? = nil) {
        conversation.append(DialogueTurn(role: "mio", text: line.text, date: now, replyID: line.id,expression:expression))
        conversation = Array(conversation.suffix(12))
        recentReplyIDs.append(line.id); recentReplyIDs = Array(recentReplyIDs.suffix(20))
        replyCount += 1; lastSpokenAt = now
    }
    public func shouldConsider(_ event: SystemEvent, now: Date) -> Bool {
        guard sessionActive else { return false }
        // Startup is also used by the explicit Connect button.
        if event.kind == "message" || event.kind == "startup" { return true }
        guard now >= quietUntil, now.timeIntervalSince(lastSpokenAt) >= 90 else { return false }
        return !["sleep", "session.inactive", "app.launch", "app.quit", "power"].contains(event.kind)
    }
    public func context(for event: SystemEvent, events: [SystemEvent], now: Date, calendar: Calendar = .current) -> DialogueContext {
        DialogueContext(now: now, calendar: calendar, sessionStarted: sessionStarted,
                        conversation: conversation, events: events, recentReplyIDs: recentReplyIDs,
                        replyCount: replyCount, quietUntil: quietUntil, excludingEvent: event.id)
    }
}
