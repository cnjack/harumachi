import XCTest
@testable import MioCore

final class DialogueTests: XCTestCase {
    private let noon = ISO8601DateFormatter().date(from:"2026-10-21T04:30:00Z")!
    private var calendar: Calendar {
        var value = Calendar(identifier:.gregorian); value.timeZone = TimeZone(identifier:"Asia/Shanghai")!; return value
    }
    private func context(at date: Date? = nil) -> DialogueContext { DialogueContext(now:date ?? noon,calendar:calendar) }

    func testClockUsesLocalTimeAndChangesAcrossMidnight() {
        let first = context(at:noon.addingTimeInterval(11*3600))
        let next = context(at:noon.addingTimeInterval(12*3600))
        XCTAssertEqual(first.localTime,"23:30"); XCTAssertEqual(first.localDate,"2026-10-21")
        XCTAssertEqual(next.localTime,"00:30"); XCTAssertEqual(next.localDate,"2026-10-22")
        XCTAssertEqual(next.weekday,"星期四"); XCTAssertEqual(next.period,.night)
        let event = SystemEvent(kind:"message",summary:"现在几点？",date:noon)
        let line = SpeechCatalog.candidates(for:event,context:context()).first!
        XCTAssertTrue(line.text.contains("12:30")); XCTAssertFalse(line.text.contains("{"))
    }
    func testAllPeriodsHaveDistinctGreetingsAndEnoughAuthoredText() {
        XCTAssertGreaterThanOrEqual(SpeechCatalog.authoredLineCount,100)
        var ids = Set<String>()
        for hour in [6,9,12,15,19,23] {
            let date = calendar.date(bySettingHour:hour,minute:0,second:0,of:noon)!
            let event = SystemEvent(kind:"startup",summary:"",date:date)
            let lines = SpeechCatalog.candidates(for:event,context:context(at:date))
            XCTAssertGreaterThanOrEqual(lines.count,4)
            XCTAssertTrue(lines.allSatisfy { $0.text.count <= 65 })
            ids.insert(lines[0].id)
        }
        XCTAssertEqual(ids.count,6)
    }
    func testFollowupKeepsThePreviousTopicAndCurrentMessageIsNotDuplicated() {
        var memory = DialogueMemory(now:noon)
        let first = SystemEvent(kind:"message",summary:"工作卡住了",date:noon)
        memory.recordUser(first)
        let before = memory.context(for:first,events:[],now:noon,calendar:calendar)
        XCTAssertTrue(before.conversation.isEmpty)
        let line = SpeechCatalog.resolve(.offline(for:first,context:before),event:first,context:before)!
        memory.recordReply(line,at:noon)
        let follow = SystemEvent(kind:"message",summary:"然后呢？",date:noon.addingTimeInterval(10))
        memory.recordUser(follow)
        let after = memory.context(for:follow,events:[],now:follow.date,calendar:calendar)
        XCTAssertEqual(after.conversation.count,2)
        XCTAssertEqual(after.conversation.first?.text,"工作卡住了")
        XCTAssertTrue(SpeechCatalog.candidates(for:follow,context:after).allSatisfy { $0.id.hasPrefix("follow_work.") })
        memory.recordReply(SpeechCatalog.candidates(for:follow,context:after)[0],at:follow.date)
        let third = SystemEvent(kind:"message",summary:"还有呢？",date:follow.date.addingTimeInterval(10))
        memory.recordUser(third)
        let thirdContext = memory.context(for:third,events:[],now:third.date,calendar:calendar)
        XCTAssertTrue(SpeechCatalog.candidates(for:third,context:thirdContext).allSatisfy { $0.id.hasPrefix("follow_work.") })
    }
    func testRecentRepliesRotateWithoutImmediateRepeatsAfterExhaustion() {
        var memory = DialogueMemory(now:noon)
        var previous: String?
        var distinct = Set<String>()
        for index in 0..<20 {
            let now = noon.addingTimeInterval(Double(index)*100)
            let event = SystemEvent(kind:"message",summary:"谢谢",date:now)
            memory.recordUser(event)
            let context = memory.context(for:event,events:[],now:now,calendar:calendar)
            XCTAssertFalse(SpeechCatalog.candidates(for:event,context:context).contains { $0.id == previous })
            let line = SpeechCatalog.resolve(.offline(for:event,context:context),event:event,context:context)!
            XCTAssertNotEqual(line.id,previous)
            memory.recordReply(line,at:now); previous = line.id; distinct.insert(line.id)
        }
        XCTAssertEqual(distinct.count,4)
    }
    func testContextIsBoundedAndDoesNotLeakUnsubmittedWindowText() throws {
        let history = (0..<40).map { DialogueTurn(role:"user",text:String(repeating:"文",count:1000),date:noon.addingTimeInterval(Double(-$0))) }
        let events = (0..<30).map { SystemEvent(kind:"app.active",summary:"SECRET WINDOW TITLE",metadata:["bundle_id":"com.example.editor","document":"SECRET DOCUMENT"],date:noon.addingTimeInterval(Double(-$0))) }
        let context = DialogueContext(now:noon,calendar:calendar,conversation:history,events:events)
        XCTAssertEqual(context.conversation.count,8); XCTAssertEqual(context.recentEvents.count,8)
        XCTAssertTrue(context.conversation.allSatisfy { $0.text.count == 300 })
        let body = try ClefClient(configuration:ClefConfiguration()).requestBody(for:events[0],context:context)
        let text = String(decoding:body,as:UTF8.self)
        XCTAssertFalse(text.contains("SECRET")); XCTAssertTrue(text.contains("com.example.editor"))
        XCTAssertLessThan(body.count,16000)
        let old = DialogueContext(now:noon.addingTimeInterval(1801),calendar:calendar,conversation:history,events:events)
        XCTAssertTrue(old.conversation.isEmpty); XCTAssertTrue(old.recentEvents.isEmpty)
    }
    func testBusyWindowSuppressesSystemChatterButAllowsUserAndResume() {
        var memory = DialogueMemory(now:noon)
        let busy = SystemEvent(kind:"message",summary:"先别说话，我先忙",date:noon)
        memory.recordUser(busy)
        let event = SystemEvent(kind:"companion.checkin",summary:"",date:noon)
        XCTAssertFalse(memory.shouldConsider(event,now:noon.addingTimeInterval(1199)))
        XCTAssertTrue(memory.shouldConsider(event,now:noon.addingTimeInterval(1201)))
        XCTAssertTrue(memory.shouldConsider(busy,now:noon.addingTimeInterval(10)))
        memory.recordUser(SystemEvent(kind:"message",summary:"可以说话了",date:noon.addingTimeInterval(20)))
        XCTAssertTrue(memory.shouldConsider(event,now:noon.addingTimeInterval(21)))
        memory.observe(SystemEvent(kind:"session.inactive",summary:"",date:noon.addingTimeInterval(22)))
        XCTAssertFalse(memory.shouldConsider(event,now:noon.addingTimeInterval(1500)))
        memory.observe(SystemEvent(kind:"wake",summary:"",date:noon.addingTimeInterval(1501)))
        XCTAssertTrue(memory.shouldConsider(event,now:noon.addingTimeInterval(1501)))
    }
    func testBackgroundCooldownDoesNotBlockDirectReplies() {
        var memory = DialogueMemory(now:noon)
        let event = SystemEvent(kind:"message",summary:"你好",date:noon)
        let line = SpeechCatalog.candidates(for:event,context:context()).first!
        memory.recordReply(line,at:noon)
        XCTAssertFalse(memory.shouldConsider(SystemEvent(kind:"app.active",summary:"",date:noon),now:noon.addingTimeInterval(89)))
        XCTAssertTrue(memory.shouldConsider(event,now:noon.addingTimeInterval(1)))
        XCTAssertTrue(memory.shouldConsider(SystemEvent(kind:"startup",summary:"重新连接 Clef",date:noon),now:noon.addingTimeInterval(1)))
        XCTAssertTrue(memory.shouldConsider(SystemEvent(kind:"app.active",summary:"",date:noon),now:noon.addingTimeInterval(91)))
    }
    func testSelectedSentenceMustComeFromCurrentCandidates() throws {
        func data(_ id: String, confidence: Double = 0.95) throws -> Data {
            try JSONSerialization.data(withJSONObject:["model":"clef-omni","answers":[
                "mood":["choice":"happy","confidence":0.95],
                "reaction":["choice":"notice","confidence":0.95],
                "utterance":["choice":id,"confidence":confidence]]])
        }
        let event = SystemEvent(kind:"message",summary:"工作有点多",date:noon)
        let choices = SpeechCatalog.candidates(for:event,context:context())
        let allowed = Set(choices.map(\.id)), chosen = choices.last!
        let decision = try ClefClient.decode(data(chosen.id),allowedUtterances:allowed)
        XCTAssertEqual(SpeechCatalog.resolve(decision,event:event,context:context())?.text,chosen.text)
        XCTAssertThrowsError(try ClefClient.decode(data("run_shell"),allowedUtterances:allowed))
        XCTAssertThrowsError(try ClefClient.decode(data("night.0"),allowedUtterances:allowed))
        XCTAssertEqual(try ClefClient.decode(data("quiet"),allowedUtterances:allowed).reaction,.none)
        // Wording probabilities can be split across multiple equally valid
        // sentences without making the high-confidence reaction unsafe.
        XCTAssertEqual(try ClefClient.decode(data(chosen.id,confidence:0.2),allowedUtterances:allowed).utteranceID,chosen.id)
        XCTAssertThrowsError(try ClefClient.decode(data(chosen.id,confidence:1.2),allowedUtterances:allowed))
        let uncertainExpression = try JSONSerialization.data(withJSONObject:["model":"clef-omni","answers":[
            "mood":["choice":"thinking","confidence":0.37],
            "reaction":["choice":"notice","confidence":0.69],
            "utterance":["choice":chosen.id,"confidence":0.36]]])
        let parsed = try ClefClient.decode(uncertainExpression,allowedUtterances:allowed)
        XCTAssertEqual(parsed.reaction,.notice); XCTAssertEqual(parsed.mood,.neutral)
        XCTAssertEqual(parsed.confidence,0.69)
        let splitReaction = try JSONSerialization.data(withJSONObject:["model":"clef-omni","answers":[
            "mood":["choice":"neutral","confidence":0.79],
            "reaction":["choice":"notice","confidence":0.52],
            "utterance":["choice":chosen.id,"confidence":0.73]]])
        XCTAssertEqual(try ClefClient.decode(splitReaction,allowedUtterances:allowed).reaction,.none)
        let direct = try ClefClient.decode(splitReaction,allowedUtterances:allowed,isDirectMessage:true)
        XCTAssertEqual(SpeechCatalog.resolve(direct,event:event,context:context())?.text,chosen.text)
    }
    func testRoutineAndInitialNetworkEventsStayQuietButRecoveryHasContext() {
        let online = SystemEvent(kind:"network",summary:"",metadata:["status":"online"],date:noon)
        XCTAssertTrue(SpeechCatalog.candidates(for:online,context:context()).isEmpty)
        let offline = SystemEvent(kind:"network",summary:"",metadata:["status":"offline"],date:noon.addingTimeInterval(-30))
        let known = DialogueContext(now:noon,calendar:calendar,events:[offline])
        XCTAssertTrue(SpeechCatalog.candidates(for:online,context:known).allSatisfy { $0.id.hasPrefix("online.") })
        XCTAssertTrue(SpeechCatalog.candidates(for:SystemEvent(kind:"thermal",summary:"",metadata:["level":"0"]),context:context()).isEmpty)
    }
    func testLiveContextualSentenceSelection() async throws {
        guard let base = ProcessInfo.processInfo.environment["MIO_TEST_CLEF_URL"] else { throw XCTSkip("Opt-in real Clef test uses only synthetic messages") }
        let client = ClefClient(configuration:ClefConfiguration(baseURL:base,timeout:15))
        var results: [[String:Any]] = []
        for (hour,message) in [(9,"早上好"),(23,"你好"),(12,"现在几点了？"),(19,"工作卡住了，有点不知道下一步怎么做")] {
            let date = calendar.date(bySettingHour:hour,minute:30,second:0,of:noon)!
            let event = SystemEvent(kind:"message",summary:message,date:date)
            let context = self.context(at:date)
            if let directory = ProcessInfo.processInfo.environment["MIO_TEST_EVIDENCE"] {
                try client.requestBody(for:event,context:context).write(to:URL(fileURLWithPath:directory).appendingPathComponent("live-request-\(hour).json"))
            }
            let decision = try await client.decide(event,context:context)
            print("LIVE \(hour) \(message): \(String(decoding:try JSONEncoder().encode(decision),as:UTF8.self))")
            let line = try XCTUnwrap(SpeechCatalog.resolve(decision,event:event,context:context))
            XCTAssertNotNil(decision.utteranceID)
            results.append(["hour":hour,"message":message,"id":line.id,"text":line.text,"confidence":decision.confidence])
        }
        var memory = DialogueMemory(now:noon)
        let first = SystemEvent(kind:"message",summary:"工作卡住了",date:noon)
        memory.recordUser(first)
        let firstContext = memory.context(for:first,events:[],now:noon,calendar:calendar)
        memory.recordReply(SpeechCatalog.candidates(for:first,context:firstContext)[0],at:noon)
        let follow = SystemEvent(kind:"message",summary:"然后呢？",date:noon.addingTimeInterval(20))
        memory.recordUser(follow)
        let nextContext = memory.context(for:follow,events:[],now:follow.date,calendar:calendar)
        let next = try await client.decide(follow,context:nextContext)
        let line = try XCTUnwrap(SpeechCatalog.resolve(next,event:follow,context:nextContext))
        XCTAssertTrue(line.id.hasPrefix("follow_work."))
        results.append(["message":"然后呢？","id":line.id,"text":line.text,"confidence":next.confidence])
        if let directory = ProcessInfo.processInfo.environment["MIO_TEST_EVIDENCE"] {
            try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:directory).appendingPathComponent("live-dialogue.json"))
        }
    }
}
