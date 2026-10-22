import Foundation

public struct VoiceConfiguration: Codable, Sendable {
    public var asrURL = "http://127.0.0.1:8311"
    public var asrModel = "qwen3-asr-0.6b"
    public var ttsURL = "http://127.0.0.1:8312"
    public var ttsModel = "mio-tts-stream"
    public var voice = "Vivian"
    public var frontendURL = "http://127.0.0.1:8313"
    public var lmURL = ""
    public var lmModel = ""
    public init() {}
    public func endpoint(_ base: String, _ path: String, local: Bool = false) throws -> URL {
        guard var c = URLComponents(string: base), ["http","https"].contains(c.scheme),
              let host=c.host, !host.isEmpty,c.user == nil,c.password == nil,c.query == nil,c.fragment == nil,
              !local || ["127.0.0.1","localhost","::1"].contains(host) else { throw VoiceError.configuration }
        c.path=c.path.trimmingCharacters(in:CharacterSet(charactersIn:"/"))
        c.path="/" + ([c.path,path].filter{!$0.isEmpty}.joined(separator:"/"))
        guard let url=c.url else { throw VoiceError.configuration };return url
    }
    public func validate() throws {
        _ = try endpoint(asrURL,"v1/audio/transcriptions",local:true)
        _ = try endpoint(ttsURL,"v1/audio/speech",local:true)
        _ = try endpoint(frontendURL,"health",local:true)
        _ = try endpoint(lmURL,"chat/completions")
        guard !lmModel.trimmingCharacters(in:.whitespaces).isEmpty else { throw VoiceError.configuration }
    }
}
public enum VoiceError: Error, LocalizedError {
    case configuration, http(Int), malformed, service(String)
    public var errorDescription: String? {
        switch self {
        case .configuration:return "请配置有效的 LM 地址与模型；本机语音服务仅接受回环地址。"
        case .http(let s):return "语音管线服务返回 HTTP \(s)"
        case .malformed:return "语音管线收到不完整的数据"
        case .service(let s):return s
        }
    }
}

/// Buffer complete clauses, not individual tokens. Keep numbers / URLs intact.
public struct SpokenClauses: Sendable {
    public private(set) var pending=""
    public init() {}
    public mutating func append(_ text: String) -> [String] {
        pending += text;var result=[String]()
        while let i=pending.indices.first(where:{index in
            let char=pending[index]
            if "。！？!?；;\n".contains(char) {return true}
            guard pending.count>=12 else{return false}
            if "，：".contains(char) {return true}
            if char=="," {
                let next=pending.index(after:index)
                return !(index>pending.startIndex && next<pending.endIndex && pending[pending.index(before:index)].isNumber && pending[next].isNumber)
            }
            return false
        }) {
            let end=pending.index(after:i),part=String(pending[..<end]);pending=String(pending[end...])
            if !part.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { result.append(part) }
        }
        // Bound latency on unpunctuated output, splitting at a word boundary if possible.
        if pending.count >= 48 {
            let boundary=pending.index(pending.startIndex,offsetBy:40)
            let prefix=pending[..<boundary]
            if !prefix.contains("://") {
                let end=prefix.lastIndex(of:" ").map{pending.index(after:$0)} ?? boundary
                result.append(String(pending[..<end]));pending=String(pending[end...])
            }
        }
        return result
    }
    public mutating func finish() -> String { defer {pending=""};return pending.trimmingCharacters(in:.whitespacesAndNewlines) }
}

/// Strip text wake prefixes and maintain the conversation window. The acoustic
/// keyword detector can also open this window before transcription completes.
public struct WakeWindow: Sendable {
    public var words=["小澪","你好澪","澪澪","小零","小玲"]
    public var expires=Date.distantPast
    public init() {}
    public mutating func accept(_ raw: String,now: Date,always: Bool = false,requirePrefix:Bool=false) -> String? {
        let text=raw.trimmingCharacters(in:.whitespacesAndNewlines)
        if ["停止聆听","结束对话","退下吧"].contains(text.trimmingCharacters(in:.punctuationCharacters)) { expires = .distantPast;return nil }
        for greeting in ["","你好","嗨","嘿"] where text.hasPrefix(greeting) {
            let addressed=String(text.dropFirst(greeting.count)).trimmingCharacters(in:.punctuationCharacters.union(.whitespacesAndNewlines))
            // Accept common ASR n/ng spelling errors only after the independent
            // acoustic xiao3-ling2 detector has confirmed the wake pronunciation.
            let aliases=words+(requirePrefix ? ["小林","小琳","小铃"]:[])
            for word in aliases.sorted(by:{$0.count>$1.count}) where addressed.hasPrefix(word) {
                expires=now.addingTimeInterval(25)
                return String(addressed.dropFirst(word.count)).trimmingCharacters(in:.punctuationCharacters.union(.whitespacesAndNewlines))
            }
        }
        if always || (!requirePrefix && now < expires) {expires=now.addingTimeInterval(25);return text}
        if requirePrefix {expires = .distantPast}
        return nil
    }
}

public struct VoiceActivityGate: Sendable {
    public enum Event: Sendable { case began, partial([Float]), ended([Float]) }
    private var pre=[Float](), utterance=[Float](), voiced=0, silence=0, sincePartial=0
    private var active=false
    public var endpointSamples=7200 // 450 ms at 16 kHz
    public init() {}
    public mutating func reset() {self=VoiceActivityGate()}
    public mutating func push(_ samples:[Float],speechDetected:Bool?=nil) -> [Event] {
        guard !samples.isEmpty else {return []}
        let rms=sqrt(samples.reduce(Float(0)){$0+$1*$1}/Float(samples.count))
        let speech=speechDetected ?? (rms>0.009)
        var events=[Event]()
        if !active {
            pre += samples;if pre.count>6400 {pre.removeFirst(pre.count-6400)}
            voiced=speech ? voiced+samples.count:0
            if voiced>=1920 {active=true;utterance=pre;pre=[];silence=0;sincePartial=0;events.append(.began)}
        } else {
            utterance += samples;sincePartial += samples.count
            silence=speech ? 0:silence+samples.count
            if silence>=endpointSamples || utterance.count>=16000*25 {
                events.append(.ended(utterance));self.reset()
            } else if sincePartial>=16000 && utterance.count>=16000 {
                events.append(.partial(utterance));sincePartial=0
            }
        }
        return events
    }
}

public enum VoicePCM {
    public static func wav(_ samples:[Float],sampleRate:Int=16000) -> Data {
        var pcm=Data(capacity:samples.count*2)
        for v in samples {var value=Int16((v.isFinite ? max(-1,min(1,v)):0)*32767).littleEndian;withUnsafeBytes(of:&value){pcm.append(contentsOf:$0)}}
        var data=Data("RIFF".utf8)
        func u32(_ x:UInt32){var n=x.littleEndian;withUnsafeBytes(of:&n){data.append(contentsOf:$0)}}
        func u16(_ x:UInt16){var n=x.littleEndian;withUnsafeBytes(of:&n){data.append(contentsOf:$0)}}
        u32(UInt32(pcm.count+36));data.append(Data("WAVEfmt ".utf8));u32(16);u16(1);u16(1);u32(UInt32(sampleRate));u32(UInt32(sampleRate*2));u16(2);u16(16);data.append(Data("data".utf8));u32(UInt32(pcm.count));data.append(pcm);return data
    }
}

public struct VoiceToolCall: Sendable {
    public var id="",name="",arguments=""
    public init() {}
}
public enum LMEvent: Sendable {case text(String),tools([VoiceToolCall])}
public struct AcousticFrame:Decodable,Sendable {public let wake:Bool;public let speech:[Bool];public let processingMs:Double}

public final class VoiceHTTP: @unchecked Sendable {
    private let session: URLSession
    public init() {
        let c=URLSessionConfiguration.ephemeral;c.timeoutIntervalForRequest=25;c.timeoutIntervalForResource=90
        c.httpMaximumConnectionsPerHost=4
        session=URLSession(configuration:c,delegate:VoiceNoRedirect(),delegateQueue:nil)
    }
    public func acoustic(_ samples:[Float],sessionID:String,configuration c:VoiceConfiguration) async throws -> AcousticFrame {
        guard samples.count==2560 else{throw VoiceError.malformed}
        var request=URLRequest(url:try c.endpoint(c.frontendURL,"frames/"+sessionID,local:true))
        request.httpMethod="POST";request.timeoutInterval=2;request.setValue("application/octet-stream",forHTTPHeaderField:"Content-Type")
        request.httpBody=VoicePCM.wav(samples).dropFirst(44)
        let (data,response)=try await session.data(for:request);try check(response)
        guard data.count<4096 else{throw VoiceError.malformed}
        let result=try JSONDecoder().decode(AcousticFrame.self,from:data)
        guard result.speech.count==5 else{throw VoiceError.malformed};return result
    }
    public func closeAcoustic(_ id:String,configuration c:VoiceConfiguration) async {
        guard let url=try? c.endpoint(c.frontendURL,"frames/"+id,local:true) else{return}
        var request=URLRequest(url:url);request.httpMethod="DELETE";request.timeoutInterval=2
        _ = try? await session.data(for:request)
    }
    public func transcribe(_ samples:[Float],configuration c:VoiceConfiguration) async throws -> String {
        let boundary="mio-\(UUID().uuidString)"
        var body=Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\n\(c.asrModel)\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8)
        body.append(VoicePCM.wav(samples));body.append(Data("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"language\"\r\n\r\nChinese\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"prompt\"\r\n\r\n人名：澪（读 líng），小澪，晴町。\r\n--\(boundary)--\r\n".utf8))
        var req=URLRequest(url:try c.endpoint(c.asrURL,"v1/audio/transcriptions",local:true));req.httpMethod="POST";req.httpBody=body;req.setValue("multipart/form-data; boundary=\(boundary)",forHTTPHeaderField:"Content-Type")
        let (data,response)=try await session.data(for:req);try check(response)
        guard data.count<256_000,let obj=try JSONSerialization.jsonObject(with:data) as? [String:Any],let text=obj["text"] as? String else {throw VoiceError.malformed}
        return text
    }
    public func language(messages:[[String:Any]],configuration c:VoiceConfiguration,key:String,tools:[[String:Any]],onEvent:@escaping (LMEvent) async throws -> Void) async throws {
        var body:[String:Any]=["model":c.lmModel,"messages":messages,"stream":true,"temperature":0.6,"max_tokens":220]
        if !tools.isEmpty {body["tools"]=tools;body["tool_choice"]="auto"}
        // TokenHub Flash defaults to reasoning; voice uses explicit non-thinking mode.
        let model=c.lmModel.lowercased().split(separator:"/").last.map(String.init) ?? ""
        if model.hasPrefix("glm") || model.hasPrefix("deepseek") {body["thinking"]=["type":"disabled"]}
        var req=URLRequest(url:try c.endpoint(c.lmURL,"chat/completions"));req.httpMethod="POST";req.httpBody=try JSONSerialization.data(withJSONObject:body);req.setValue("application/json",forHTTPHeaderField:"Content-Type")
        if !key.isEmpty {req.setValue("Bearer \(key)",forHTTPHeaderField:"Authorization")}
        var calls=[Int:VoiceToolCall](),gotFinish=false
        try await sse(req) {obj in
            guard let choices=obj["choices"] as? [[String:Any]],let choice=choices.first else {return}
            if let finish=choice["finish_reason"] as? String {gotFinish=true;if finish=="length" {throw VoiceError.service("LM 输出达到长度上限，请把问题拆短。")}}
            guard let delta=choice["delta"] as? [String:Any] else {return}
            if let content=delta["content"] as? String,!content.isEmpty {try await onEvent(.text(content))}
            for call in delta["tool_calls"] as? [[String:Any]] ?? [] {
                guard let index=call["index"] as? Int,index>=0,index<3 else {throw VoiceError.malformed}
                var value=calls[index] ?? VoiceToolCall()
                if let id=call["id"] as? String {value.id=id}
                if let f=call["function"] as? [String:Any] {value.name += f["name"] as? String ?? "";value.arguments += f["arguments"] as? String ?? ""}
                guard value.arguments.utf8.count<8192 else {throw VoiceError.malformed};calls[index]=value
            }
        }
        guard gotFinish else {throw VoiceError.malformed}
        if !calls.isEmpty {try await onEvent(.tools(calls.sorted{$0.key<$1.key}.map(\.value)))}
    }
    public func speech(_ text:String,configuration c:VoiceConfiguration,onPCM:@escaping (Data) async throws -> Void) async throws {
        var req=URLRequest(url:try c.endpoint(c.ttsURL,"v1/audio/speech",local:true));req.httpMethod="POST";req.setValue("application/json",forHTTPHeaderField:"Content-Type")
        req.httpBody=try JSONSerialization.data(withJSONObject:["model":c.ttsModel,"input":text.replacingOccurrences(of:"澪",with:"玲"),"voice":c.voice,"language":"Chinese","response_format":"pcm","stream_format":"sse","options":["stream_frames_per_event":6,"stream_chunk_policy":"grow"]])
        var gotAudio=false,done=false
        try await sse(req) {obj in
            if obj["type"] as? String=="speech.audio.done" {done=true}
            if obj["type"] as? String=="speech.audio.delta" {
                guard let value=obj["audio"] as? String,let data=Data(base64Encoded:value),data.count%2==0 else {throw VoiceError.malformed}
                gotAudio = gotAudio || !data.isEmpty;try await onPCM(data)
            }
        }
        guard gotAudio && done else {throw VoiceError.malformed}
    }
    private func sse(_ req:URLRequest,receive:([String:Any]) async throws -> Void) async throws {
        let (bytes,response)=try await session.bytes(for:req);try check(response)
        var total=0
        for try await line in bytes.lines {
            try Task.checkCancellation();total += line.utf8.count
            guard line.utf8.count<2_000_000,total<32_000_000 else {throw VoiceError.malformed}
            guard line.hasPrefix("data:") else {continue}
            let value=line.dropFirst(5).trimmingCharacters(in:.whitespaces)
            if value=="[DONE]" {return}
            guard let data=value.data(using:.utf8),let obj=try JSONSerialization.jsonObject(with:data) as? [String:Any] else {throw VoiceError.malformed}
            if obj["error"] != nil || obj["type"] as? String=="error" {throw VoiceError.service("语音服务无法完成本轮请求，请检查服务状态。")}
            try await receive(obj)
        }
    }
    private func check(_ response:URLResponse) throws {
        guard let http=response as? HTTPURLResponse else {throw VoiceError.malformed}
        guard (200..<300).contains(http.statusCode) else {throw VoiceError.http(http.statusCode)}
    }
}
private final class VoiceNoRedirect:NSObject,URLSessionTaskDelegate,@unchecked Sendable {
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping (URLRequest?)->Void){completionHandler(nil)}
}
