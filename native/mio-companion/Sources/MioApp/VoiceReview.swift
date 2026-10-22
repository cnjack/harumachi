import Foundation
import AppKit
import MioCore

extension AppDelegate {
    @MainActor func runVoiceReview(at directory:URL) {
        Task {
            let env=ProcessInfo.processInfo.environment
            let voice=state.voice
            state.baseURL="http://127.0.0.1:9"
            do {
                guard env["MIO_VOICE_TEST_SILENT"]=="1",voice.configured else{throw VoiceError.configuration}
                @MainActor func waitForReply() async throws {
                    let deadline=Date().addingTimeInterval(35)
                    while voice.busy,Date()<deadline {try await Task.sleep(nanoseconds:50_000_000)}
                    guard !voice.busy,voice.error.isEmpty else{throw VoiceError.service(voice.error.isEmpty ? "voice timeout":voice.error)}
                }
                if let fixture=env["MIO_VOICE_REPLAY_WAV"] {try await voice.replayForReview(VoiceAudio.fixture16k(URL(fileURLWithPath:fixture)))}
                else {voice.submit("你好，今天有点累，想和你聊一会。")}
                try await waitForReply()
                guard voice.playbackBlocks>2,voice.maximumMouth>0.02 else{throw VoiceError.service("No streamed playback or mouth movement")}
                let firstBlocks=voice.playbackBlocks
                let replayTranscript=voice.transcript
                voice.submit("请给我一段很长的鼓励。")
                let deadline=Date().addingTimeInterval(10)
                while voice.playbackBlocks<=firstBlocks,Date()<deadline {try await Task.sleep(nanoseconds:20_000_000)}
                guard voice.playbackBlocks>firstBlocks else{throw VoiceError.service("Interruption test had no active audio")}
                let cancel=Date();voice.interrupt();let blocks=voice.playbackBlocks
                try await Task.sleep(nanoseconds:400_000_000)
                guard !voice.busy,voice.playbackBlocks==blocks,state.voiceMouth==0 else{throw VoiceError.service("Cancelled audio continued")}
                let cancelCheckMs=Date().timeIntervalSince(cancel)*1000
                let blocksAfterCancel=voice.playbackBlocks-blocks
                voice.submit("查看一下进程，Mio 是否在运行？")
                try await waitForReply()
                guard voice.executedTools.contains("list_processes") else{throw VoiceError.service("Process tool was not executed")}
                var websiteResult="not run"
                if env["MIO_VOICE_WEB_TEST"]=="1" {
                    var call=VoiceToolCall();call.name="read_website";call.arguments="{\"url\":\"https://example.com\"}"
                    websiteResult=await VoiceTools.execute(call,userText:"看看 https://example.com")
                    guard websiteResult.contains("Example Domain") else{throw VoiceError.service("Public website read failed")}
                    let rejected=await VoiceTools.execute(call,userText:"你好")
                    guard !rejected.contains("Example Domain") else{throw VoiceError.service("Website host authorization failed")}
                    do {
                        _ = try VoiceTools.approvedURL("https://example.com/?conversation=private",userText:"看看 https://example.com")
                        throw VoiceError.service("Unrequested website query accepted")
                    } catch VoiceError.configuration { /* expected */ }
                }
                let report:[String:Any]=["streamedBlocks":voice.playbackBlocks,"maximumMouth":voice.maximumMouth,"lastLatency":voice.lastLatency,"interruptVerifiedAfterMs":cancelCheckMs,"cancelledBlocksAfter400ms":blocksAfterCancel,"executedTools":voice.executedTools,"listening":voice.listening,"microphoneCaptured":false,"audioOutputMuted":true,"history":voice.historyForReview,"rendererFrames":state.frames,"lmModel":voice.configuration.lmModel,"lmBase":voice.configuration.lmURL]
                try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("native-pipeline.json"))
                if env["MIO_VOICE_REPLAY_WAV"] != nil {try replayTranscript.write(to:directory.appendingPathComponent("acoustic-transcript.txt"),atomically:true,encoding:.utf8)}
                try websiteResult.write(to:directory.appendingPathComponent("website.txt"),atomically:true,encoding:.utf8)
                voice.showSettings=true
                try await Task.sleep(nanoseconds:200_000_000)
                try saveOwnWindow(dashboard,to:directory.appendingPathComponent("dashboard.png"))
                state.stop();exit(0)
            } catch {fputs("Voice review failed: \(error.localizedDescription)\n",stderr);state.stop();exit(1)}
        }
    }
}
