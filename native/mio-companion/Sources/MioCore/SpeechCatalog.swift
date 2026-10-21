import Foundation

public struct DialogueLine: Sendable {
    public let id: String
    public let text: String
    public let mood: Mood
    public let reaction: Reaction
}

/// Clef selects a sentence from the current eligible set, including silence.
/// Text stays authored, bounded and in-character; no executable model output.
public enum SpeechCatalog {
    private struct Group {
        let name: String
        let mood: Mood
        let reaction: Reaction
        let lines: [String]
    }
    private static let groups: [Group] = [
        Group(name: "dawn", mood: .happy, reaction: .greet, lines: [
            "早呀。一天才刚开始，先给自己留一点不赶路的时间。",
            "这么早就见到你了。今天从一件小事慢慢开始吧。",
            "早安，我是澪。你准备你的，我在旁边陪一会儿。",
            "晴町的早晨总让我想起刚擦干净的公告栏。今天也想认真过。"
        ]),
        Group(name: "morning", mood: .happy, reaction: .greet, lines: [
            "早上好。今天想先做哪一件事？",
            "上午好，见到你啦。我们把今天分成小小的几段吧。",
            "早呀。先不用想着做完全部，把第一步找出来就好。",
            "新的一天，又能和你打个招呼了。今天也请多关照。",
            "早上好！今天也加油哦。……我也在给自己打气。"
        ]),
        Group(name: "noon", mood: .happy, reaction: .greet, lines: [
            "中午好。要是还没吃饭，忙完这一小段就去吃点吧。",
            "到午间啦。事情可以分段做，午饭也值得留个位置。",
            "中午见到你了。现在想聊两句，还是安静待一会儿？",
            "午间问候送到。愿你接下来这一段，能稍微从容一点。"
        ]),
        Group(name: "afternoon", mood: .happy, reaction: .greet, lines: [
            "下午好。你忙你的，有想说的话再叫我。",
            "又到下午啦。把手边这一件做好，就已经很不错。",
            "下午好呀。喝口水，再看看下一步从哪里开始。",
            "这个下午，我也在。想听点晴町的小事吗？"
        ]),
        Group(name: "evening", mood: .happy, reaction: .greet, lines: [
            "晚上好。今天过得怎么样，想和我说一点吗？",
            "傍晚啦。如果还有事情，我们就一件一件收尾。",
            "晚上见到你了。给今天留一件让自己舒服的小事吧。",
            "晚上好。是准备继续忙一会儿，还是已经可以歇下了？"
        ]),
        Group(name: "night", mood: .neutral, reaction: .greet, lines: [
            "夜深了。要是还在忙，就给自己定个舒服的收尾时间吧。",
            "这么晚还见到你。我把声音放轻一点，陪你收个尾。",
            "夜里也来打个招呼。困了就先休息，事情可以明天再接上。",
            "晚上好。现在适合慢一点，也适合对自己宽容一点。",
            "已经是夜间啦。今天做到这里的话，也完全可以。"
        ]),
        Group(name: "weekend", mood: .happy, reaction: .notice, lines: [
            "周末好呀。今天想留一点时间，做只因为喜欢才做的事情吗？",
            "周末也见到你了。不管今天忙不忙，都给自己留一点空当吧。",
            "要是今天能歇一歇，散散步、吃点喜欢的，都很不错。"
        ]),
        Group(name: "focus", mood: .neutral, reaction: .focus, lines: [
            "我先安静待着。你想聊的时候，再叫我就好。",
            "慢慢来，眼下只需要处理手边这一件。",
            "不用分心照顾我。留一点注意力给你正在做的事。",
            "这一小段，就专心走完吧。我在旁边。",
            "事情多的时候，先找一个能开始的小地方。",
            "我不催进度。按你自己的节奏来。"
        ]),
        Group(name: "work", mood: .thinking, reaction: .notice, lines: [
            "事情有点多的话，先挑最需要完成的一件，好吗？",
            "先把卡住的地方说出来吧。是还没想清楚，还是已经试过却不顺？",
            "把下一步缩到十分钟能开始的大小，可能就没那么沉了。",
            "要不要先列三件事，再只看排在最前面的那件？",
            "有些事想很久也会打结。先记下卡在哪里，再换个小角度看看。",
            "我听着呢。你想梳理下一步，还是只想吐槽一小会儿？",
            "今天先做到一个清楚的停点，也算认真收尾了。",
            "如果你愿意，可以把最难开始的那一步告诉我。"
        ]),
        Group(name: "rest", mood: .concerned, reaction: .rest, lines: [
            "累了的话，先让肩膀松一松，喝口水吧。",
            "不用硬撑着一直往前。离开屏幕一小会儿也可以。",
            "先歇一会儿吧。回来以后，我们再找下一小步。",
            "要不要看看远一点的地方，让眼睛也放个小假？",
            "手边方便的话，起身走两步，再决定要不要继续。",
            "今天已经花了不少心力吧。给自己一点喘口气的空当。",
            "休息不需要等到事情全做完。现在也能留两分钟给自己。",
            "要是已经困了，就别和睡意较劲啦。"
        ]),
        Group(name: "comfort", mood: .concerned, reaction: .notice, lines: [
            "听起来不太顺。你想说的话，我会认真听。",
            "先不用急着把心情整理好。慢慢说也没关系。",
            "这件事让你很在意吧。最难受的是哪一部分？",
            "今天不顺，也不代表你做什么都不行。先缓一口气。",
            "如果现在不想找办法，我们就先不找。说说发生了什么也好。",
            "有时候只说一句“我有点难过”，也已经是在照顾自己了。",
            "你想要一点建议，还是希望我先听你说？",
            "先别把所有错都算到自己身上。我们可以一件一件看。"
        ]),
        Group(name: "celebrate", mood: .happy, reaction: .notice, lines: [
            "做完啦？太好了，给这一小步认真庆祝一下。",
            "听见这个消息，我也替你高兴。辛苦的那一段有着落了。",
            "这份开心值得多留一会儿。你最满意的是哪一点？",
            "好耶！先享受一下完成的感觉，再想下一件事。",
            "又往前走了一步呢。要不要给今天留一条小记录？",
            "恭喜你。那些慢慢做的部分，终于接起来了。"
        ]),
        Group(name: "thanks", mood: .happy, reaction: .notice, lines: [
            "不客气呀。能陪你说上几句，我也很开心。",
            "收到这句谢谢啦。今天也对自己好一点吧。",
            "嗯！那就把这份好心情留着，慢慢往下走。",
            "不用客气。你愿意告诉我这些，我很珍惜。"
        ]),
        Group(name: "farewell", mood: .happy, reaction: .notice, lines: [
            "好，先去忙你的生活吧。下次见。",
            "好，先把手边的事放一放。愿你接下来能好好休息。",
            "那就先聊到这里。希望你接下来轻松一点。",
            "回头见。今天辛苦啦。"
        ]),
        Group(name: "quiet", mood: .neutral, reaction: .notice, lines: [
            "好，我先安静二十分钟。你主动找我时，我还是会回应。",
            "收到。接下来二十分钟不主动打扰，你忙完再叫我。",
            "嗯，先让你专心。二十分钟内，我只回应你发来的话。"
        ]),
        Group(name: "resume", mood: .happy, reaction: .notice, lines: [
            "我在呢。想继续刚才的话题，还是换个轻松一点的？",
            "好呀，可以继续聊了。你现在最想说什么？",
            "收到，恢复陪伴啦。今天有什么小事想分享吗？"
        ]),
        Group(name: "persona", mood: .happy, reaction: .notice, lines: [
            "我是澪，在晴町负责社区活动联络。现在也来你的桌面串个门。",
            "我喜欢把零散的小事慢慢凑起来。就像准备一场大家都能来的集市。",
            "晴町的公告栏，总让我觉得“还有事情可以一起做”，很踏实。",
            "如果说一个愿望，我想让晴町的夏祭重新热闹起来。",
            "我大概是那种会认真写清单，写完又在旁边画小花的人。",
            "我不太擅长漂亮的大道理。陪你把眼前的小事说清楚，倒是愿意试试。"
        ]),
        Group(name: "town", mood: .happy, reaction: .notice, lines: [
            "想起晴町的河边长椅了。那里很适合坐着，把一件小事慢慢说完。",
            "要是在晴町办集市，你想摆吃的摊，还是卖自己做的小东西？",
            "我总觉得，夏祭准备时的那些小纸条，也该被好好收起来。",
            "晴町的故事里，我负责联系大家。有时候最难的是问出第一句“你愿意来吗”。",
            "如果给晴町的公告栏贴一张新海报，你会在上面写什么？",
            "想到集市散场还没收好的桌子，我就想笑。忙归忙，人来过的感觉很好。"
        ]),
        Group(name: "follow_work", mood: .thinking, reaction: .notice, lines: [
            "那就接着刚才那件事。先选一个最小步骤，做完再决定下一步。",
            "接下来可以把“必须今天做”和“可以再等等”分开。哪一件最明确？",
            "先不用规划全部。你觉得现在能动手的第一步是什么？"
        ]),
        Group(name: "follow_comfort", mood: .concerned, reaction: .notice, lines: [
            "嗯，我还在听。刚才那件事里，你最希望被理解的是什么？",
            "那就慢慢接着说，不用急着得出结论。",
            "如果你愿意，我们可以先说最让你放不下的那一小段。"
        ]),
        Group(name: "follow_rest", mood: .neutral, reaction: .notice, lines: [
            "好。就先休息两分钟，不用给这段空白安排任务。",
            "回来后再看一眼状态吧。如果还是累，就把步子放小一点。",
            "嗯，先照顾好自己。接下来的事，等缓过来再想。"
        ]),
        Group(name: "follow_town", mood: .happy, reaction: .notice, lines: [
            "那我们继续聊晴町。你更想听集市，还是那场想重新办起来的夏祭？",
            "说到这里，我又想到河边那几张长椅。有人愿意坐下来，故事才有下一句。",
            "要是换你来写邀请，第一句话会怎么写呢？"
        ]),
        Group(name: "follow", mood: .thinking, reaction: .notice, lines: [
            "嗯，我们接着刚才的话说。你最想多聊哪一点？",
            "我记着前面的话。你想继续细说，还是一起想个下一步？",
            "好呀。那你现在的想法，比刚才更清楚一点了吗？"
        ]),
        Group(name: "time", mood: .neutral, reaction: .notice, lines: [
            "现在是 {time}。你想安排接下来这一小段时间吗？",
            "我这里的当地时间是 {time}，今天{weekday}。",
            "看了下时间，{time} 啦。按你自己的节奏来。"
        ]),
        Group(name: "date", mood: .neutral, reaction: .notice, lines: [
            "今天是 {date}，{weekday}。",
            "日历翻到 {date} 了，今天{weekday}。有什么想留在今天的小事吗？"
        ]),
        Group(name: "session", mood: .neutral, reaction: .notice, lines: [
            "这次会话已经过了大约 {minutes} 分钟。中间想歇一歇也可以。",
            "从这次开始陪伴到现在，大约 {minutes} 分钟啦。你还好吗？"
        ]),
        Group(name: "offline", mood: .concerned, reaction: .notice, lines: [
            "网络好像断开了。如果手边的事情需要联网，可以先缓一缓。",
            "收到网络断开的消息。暂时不用一直重试，等它恢复吧。"
        ]),
        Group(name: "online", mood: .happy, reaction: .notice, lines: [
            "网络恢复啦。刚才等着联网的事，现在可以再试试。",
            "连接回来了。我们把刚才停下的那一步接上吧。"
        ]),
        Group(name: "thermal", mood: .concerned, reaction: .notice, lines: [
            "系统提示温度压力有些高。方便的话，让电脑和你都缓一会儿。",
            "电脑发来温度提醒了。可以考虑先收一收同时进行的任务。"
        ]),
        Group(name: "general", mood: .neutral, reaction: .notice, lines: [
            "我在听。你想从哪一部分说起？",
            "收到你的话了。愿意再多说一点吗？",
            "嗯，你希望我陪你聊聊，还是一起梳理眼前的事情？",
            "这件事对你来说，最在意的是什么？",
            "慢慢说，不用一下子把前因后果都整理好。",
            "我可能还没完全懂。你能再给我一点上下文吗？"
        ])
    ]

    public static var authoredLineCount: Int { groups.reduce(0) { $0+$1.lines.count } }
    public static func topic(_ text: String) -> String? {
        let value = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let rules: [(String,[String])] = [
            ("quiet",["安静点","先别说","别打扰","让我专心","我先忙","不要说话","不要一直提醒"]),
            ("resume",["继续聊","可以说话","陪我聊","聊聊天","解除安静"]),
            ("time",["几点","现在时间","当前时间"]),
            ("date",["几号","星期几","什么日期","今天日期"]),
            ("session",["陪了多久","陪伴多久","开了多久"]),
            ("celebrate",["完成了","做完了","搞定","成功了","解决了","通过了","好开心"]),
            ("comfort",["难过","伤心","焦虑","烦躁","不开心","失败","委屈","压力好大"]),
            ("rest",["好累","有点累","很累","困了","疲惫","想休息"]),
            ("farewell",["晚安","再见","去睡","先走了","下次聊"]),
            ("thanks",["谢谢","感谢","多谢"]),
            ("persona",["你是谁","介绍自己","你的名字","你喜欢","你的性格"]),
            ("town",["晴町","夏祭","集市","公告栏"]),
            ("greeting",["你好","早安","早上好","下午好","晚上好","中午好","早呀"]),
            ("work",["加班","工作","代码","项目","忙不过","任务","卡住","bug"])
        ]
        return rules.first { $0.1.contains(where: value.contains) }?.0
    }
    private static func isFollowup(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return ["嗯","好","好的","然后呢","接着说","继续","那怎么办","怎么做","为什么","还有呢"].contains(value)
    }
    private static func category(for event: SystemEvent, context: DialogueContext) -> String? {
        if event.kind == "message" {
            if let found = topic(event.summary) { return found == "greeting" ? context.period.rawValue : found }
            if isFollowup(event.summary), !context.conversation.isEmpty {
                let previous = context.conversation.last(where: { $0.role == "user" }).flatMap { topic($0.text) }
                    ?? context.conversation.last(where: { $0.role == "mio" })?.replyID?.components(separatedBy: ".").first
                switch previous {
                case "work", "focus", "follow_work": return "follow_work"
                case "comfort", "follow_comfort": return "follow_comfort"
                case "rest", "follow_rest": return "follow_rest"
                case "town", "persona", "follow_town": return "follow_town"
                default: return "follow"
                }
            }
            return "general"
        }
        switch event.kind {
        case "startup", "wake", "session.active", "time.period": return context.period.rawValue
        case "companion.checkin": return context.period == .night ? "night" : "town"
        case "break.due": return "rest"
        case "app.active": return "focus"
        case "network":
            if event.metadata["status"] == "offline" { return "offline" }
            return context.recentEvents.contains { $0.kind == "network" && $0.metadata["status"] == "offline" } ? "online" : nil
        case "thermal": return (Int(event.metadata["level"] ?? "0") ?? 0) >= 2 ? "thermal" : nil
        default: return nil
        }
    }
    private static func lines(in category: String, context: DialogueContext) -> [DialogueLine] {
        guard let group = groups.first(where: { $0.name == category }) else { return [] }
        let lines = group.lines.enumerated().map { index, text in
            DialogueLine(id: category+"."+String(index), text: text
                .replacingOccurrences(of: "{time}", with: context.localTime)
                .replacingOccurrences(of: "{date}", with: context.localDate)
                .replacingOccurrences(of: "{weekday}", with: context.weekday)
                .replacingOccurrences(of: "{minutes}", with: String(context.sessionMinutes)),
                mood: group.mood, reaction: group.reaction)
        }
        guard !lines.isEmpty else { return [] }
        let offset = context.replyCount % lines.count
        let rotated = Array(lines[offset...])+Array(lines[..<offset])
        let fresh = rotated.filter { !context.recentReplyIDs.contains($0.id) }
        if !fresh.isEmpty { return fresh }
        // When a small category is exhausted, use the least recently spoken
        // sentence, never jump back to the last one merely because of cycling.
        return rotated.filter { $0.id != context.recentReplyIDs.last }.sorted {
            (context.recentReplyIDs.lastIndex(of:$0.id) ?? -1) < (context.recentReplyIDs.lastIndex(of:$1.id) ?? -1)
        }
    }
    public static func candidates(for event: SystemEvent, context: DialogueContext) -> [DialogueLine] {
        guard let category = category(for:event,context:context) else { return [] }
        var result = lines(in:category,context:context)
        if context.weekend && DayPeriod(rawValue:category) != nil {
            result += lines(in:"weekend",context:context)
        }
        // Let Clef recognize message meanings beyond the small offline lexicon.
        if category == "general" {
            for other in ["work","comfort","rest","celebrate","persona","town"] {
                if let line = lines(in:other,context:context).first { result.append(line) }
            }
        }
        return Array(result.prefix(12))
    }
    public static func resolve(_ decision: Decision, event: SystemEvent, context: DialogueContext) -> DialogueLine? {
        guard decision.reaction != .none, event.kind == "message" || decision.confidence >= 0.55 else { return nil }
        let eligible = candidates(for:event,context:context)
        if let id = decision.utteranceID, let line = eligible.first(where: { $0.id == id }) { return line }
        return eligible.first
    }
}
