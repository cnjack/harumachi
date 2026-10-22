import XCTest
@testable import MioCore

final class VoicePipelineTests:XCTestCase {
    func testWakePrefixAndExpiration() {
        var gate=WakeWindow();let now=Date(timeIntervalSince1970:1000)
        XCTAssertNil(gate.accept("我昨天看见小澪了",now:now))
        XCTAssertEqual(gate.accept("小澪，今天好吗？",now:now),"今天好吗")
        XCTAssertEqual(gate.accept("我今天有点累。",now:now.addingTimeInterval(12)),"我今天有点累。")
        XCTAssertNil(gate.accept("电视里的对话",now:now.addingTimeInterval(40)))
        XCTAssertEqual(gate.accept("小澪",now:now),"")
        XCTAssertNil(gate.accept("停止聆听",now:now))
        XCTAssertNil(gate.accept("普通话",now:now.addingTimeInterval(1)))
    }
    func testClausesDoNotWaitForFullReplyOrLoseText() {
        var c=SpokenClauses();var out=[String]()
        let input="我在这里。今天过得怎么样？我们可以慢慢聊。"
        for char in input {out += c.append(String(char))}
        XCTAssertEqual(out.count,3);XCTAssertEqual(out.joined()+c.finish(),input)
        var number=SpokenClauses()
        XCTAssertEqual(number.append("是 3.14，接下来还要继续说明一些内容"),["是 3.14，"])
        XCTAssertEqual(number.finish(),"接下来还要继续说明一些内容")
        var link=SpokenClauses()
        XCTAssertTrue(link.append("地址 https://example.com，接下来我们继续说明").first=="地址 https://example.com，")
        var thousands=SpokenClauses()
        XCTAssertEqual(thousands.append("当前有 1,234 个元素。"),["当前有 1,234 个元素。"])
    }
    func testActivityRejectsClickAndKeepsSpeechPreroll() {
        var vad=VoiceActivityGate();let silence=Array(repeating:Float(0),count:320),speech=Array(repeating:Float(0.1),count:320)
        for _ in 0..<20 {XCTAssertTrue(vad.push(silence).isEmpty)}
        XCTAssertTrue(vad.push(speech).isEmpty)
        for _ in 0..<20 {XCTAssertTrue(vad.push(silence).isEmpty)}
        var began=0,ended=[[Float]]()
        for _ in 0..<30 {for e in vad.push(speech) {if case .began=e {began += 1}}}
        for _ in 0..<30 {for e in vad.push(silence) {if case .ended(let pcm)=e {ended.append(pcm)}}}
        XCTAssertEqual(began,1);XCTAssertEqual(ended.count,1);XCTAssertGreaterThan(ended[0].count,16000)
    }
    func testLongSpeechIsBoundedAndWavHasCorrectFormat() {
        var vad=VoiceActivityGate();var finalCount=0
        for _ in 0..<1300 {for e in vad.push(Array(repeating:0.1,count:320)) {if case .ended(let pcm)=e {finalCount += 1;XCTAssertLessThanOrEqual(pcm.count,400320)}}}
        XCTAssertEqual(finalCount,1)
        let wav=VoicePCM.wav([0,1,-1]);XCTAssertEqual(wav.count,50)
        XCTAssertEqual(String(data:wav.prefix(4),encoding:.utf8),"RIFF")
        XCTAssertEqual(Array(wav.suffix(6)),[0,0,255,127,1,128])
    }
    func testConfigurationNeverSendsAudioRemoteOrCredentialsInURL() {
        var c=VoiceConfiguration();c.lmURL="https://example.com/v1";c.lmModel="test"
        XCTAssertNoThrow(try c.validate())
        XCTAssertEqual(try c.endpoint(c.lmURL,"chat/completions").absoluteString,"https://example.com/v1/chat/completions")
        c.asrURL="https://example.com";XCTAssertThrowsError(try c.validate())
        c.asrURL="http://127.0.0.1:8311";c.lmURL="https://secret@example.com/v1";XCTAssertThrowsError(try c.validate())
        c.lmURL="https://example.com/v1?token=secret";XCTAssertThrowsError(try c.validate())
    }
    func testAudioOwnsMouthIncludingSilentFrames() {
        var pose=RigPose(time:1,speaking:true);pose.audioMouth=0
        XCTAssertEqual(pose.mouthAmount,0)
        pose.audioMouth=0.8;XCTAssertEqual(pose.mouthAmount,0.8)
        pose.audioMouth=2;XCTAssertEqual(pose.mouthAmount,1)
    }
    func testNonFiniteMicrophoneSamplesDoNotCrash() {
        XCTAssertEqual(Array(VoicePCM.wav([.nan,.infinity,-.infinity]).suffix(6)),Array(repeating:0,count:6))
    }
    func testNeuralVADOverridesEnergyGate() {
        var vad=VoiceActivityGate();var began=false
        for _ in 0..<4 {for e in vad.push(Array(repeating:0.0001,count:512),speechDetected:true) {if case .began=e {began=true}}}
        XCTAssertTrue(began)
        var noise=VoiceActivityGate()
        for _ in 0..<40 {XCTAssertTrue(noise.push(Array(repeating:0.3,count:512),speechDetected:false).isEmpty)}
    }
    func testFragmentedSSEAndToolCallsWhenFixtureEnabled() async throws {
        guard let base=ProcessInfo.processInfo.environment["MIO_VOICE_FIXTURE_URL"] else{throw XCTSkip("Opt-in local LM transport fixture")}
        var c=VoiceConfiguration();c.lmURL=base;c.lmModel="fixture"
        let http=VoiceHTTP();var text="",calls=[VoiceToolCall]()
        try await http.language(messages:[["role":"user","content":"你好"]],configuration:c,key:"",tools:[]){event in if case .text(let value)=event {text += value}}
        XCTAssertEqual(text,"我在这里。今天辛苦了，我们慢慢聊。")
        try await http.language(messages:[["role":"user","content":"查看进程"]],configuration:c,key:"",tools:[]){event in if case .tools(let value)=event {calls=value}}
        XCTAssertEqual(calls.count,1);XCTAssertEqual(calls.first?.name,"list_processes");XCTAssertEqual(calls.first?.arguments,"{\"query\":\"Mio\"}")
        for model in ["fixture-http-error","fixture-truncated"] {
            c.lmModel=model
            do {try await http.language(messages:[["role":"user","content":"你好"]],configuration:c,key:"",tools:[]){_ in};XCTFail("Accepted failed/truncated stream")}
            catch let error as VoiceError {
                switch error {case .http(503),.malformed:break;default:XCTFail("Unexpected error")}
            }
        }
    }
    func testRealLocalSpeechRoundtripWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["MIO_VOICE_LIVE_TEST"]=="1" else{throw XCTSkip("Opt-in local audio services; no microphone or playback")}
        let c=VoiceConfiguration(),http=VoiceHTTP();var audio=Data(),chunks=0
        try await http.speech("我在这里，今天过得怎么样？",configuration:c){data in audio.append(data);chunks += 1}
        XCTAssertGreaterThan(chunks,2);XCTAssertGreaterThan(audio.count,10000)
        let bytes=[UInt8](audio)
        // The TTS contract is signed 16-bit, 24 kHz mono; resample for ASR.
        var samples=[Float]()
        for i in stride(from:0,to:bytes.count/2,by:3) {
            for offset in [0,1] where i+offset<bytes.count/2 {
                let p=(i+offset)*2;samples.append(Float(Int16(bitPattern:UInt16(bytes[p])|UInt16(bytes[p+1])<<8))/32768)
            }
        }
        let text=try await http.transcribe(samples,configuration:c)
        XCTAssertTrue(text.contains("今天"));XCTAssertTrue(text.contains("怎么样"))
    }
}
