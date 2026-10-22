import SwiftUI

struct VoicePanel:View {
    @ObservedObject var voice:VoiceController
    var body:some View {
        VStack(alignment:.leading,spacing:7) {
            HStack(spacing:8) {
                Image(systemName:voice.listening ? "mic.fill":"mic.slash").foregroundStyle(voice.listening ? Color.red:Color.secondary)
                Text("语音对话").font(.system(size:12,weight:.medium))
                Text(voice.status).font(.system(size:11)).foregroundStyle(.secondary)
                Spacer()
                Button(voice.listening ? "停止聆听":"开启语音"){if voice.listening {voice.stopListening()} else {voice.startListening()}}
                if voice.busy {Button("打断",action:voice.interrupt)}
                Button("设置"){voice.showSettings.toggle()}
            }.controlSize(.small)
            if !voice.transcript.isEmpty {Text("你："+voice.transcript).font(.system(size:11)).lineLimit(2)}
            if !voice.error.isEmpty {Text(voice.error).font(.system(size:11)).foregroundStyle(.orange)}
            if voice.showSettings {
                VStack(alignment:.leading,spacing:7) {
                    Text("对话模型 · OpenAI 兼容接口").font(.system(size:11,weight:.medium))
                    HStack {TextField("Base URL（包含 /v1 等前缀）",text:$voice.configuration.lmURL);TextField("模型 ID",text:$voice.configuration.lmModel).frame(width:130)}
                    SecureField(voice.keySaved ? "密钥已保存；留空保留":"API Key（仅保存到钥匙串）",text:$voice.keyInput)
                    HStack {Text("识别").font(.system(size:10));TextField("ASR 地址",text:$voice.configuration.asrURL);Text("合成").font(.system(size:10));TextField("TTS 地址",text:$voice.configuration.ttsURL)}
                    HStack {
                        Toggle("朗读回复",isOn:$voice.speechOutput)
                        Toggle("免唤醒连续聆听",isOn:$voice.continuous)
                        Spacer();Button("保存",action:voice.save)
                    }.font(.system(size:11))
                    Text("默认说「小澪」（xiǎo líng）唤醒，回复后 25 秒内可直接接话。语音留在本机，仅唤醒后的文字发送给所配置的 LM 和现有 Clef。暂停或锁屏会停止采集。").font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    if !voice.lastLatency.isEmpty {Text(voice.lastLatency).font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary)}
                }.textFieldStyle(.roundedBorder).padding(9).background(.black.opacity(0.025),in:RoundedRectangle(cornerRadius:8))
            }
        }
    }
}
