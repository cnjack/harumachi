import AVFoundation
import MioCore

/// Input and output share one engine so Apple's voice processing sees the
/// assistant's actual playback reference. No system-volume changes or recordings.
@MainActor final class VoiceAudio {
    private var engine=AVAudioEngine(),player=AVAudioPlayerNode()
    private let playbackFormat=AVAudioFormat(standardFormatWithSampleRate:24000,channels:1)!
    private var tapped=false,epoch=0
    private var queuedFrames:Int64=0
    private var playedFrames:Int64=0
    private var meterTimer:Timer?
    private var envelopes:[(Int64,Float)]=[]
    private(set) var pendingMarkers=0
    var onSamples:(([Float])->Void)?
    var onLevel:((Float)->Void)?
    var queuedSeconds:Double {Double(queuedFrames-playedFrames)/24000}
    init(){engine.attach(player);engine.connect(player,to:engine.mainMixerNode,format:playbackFormat);if ProcessInfo.processInfo.environment["MIO_VOICE_TEST_SILENT"]=="1" {engine.mainMixerNode.outputVolume=0}}
    func start(capture:Bool) throws {
        if capture && !tapped {
            engine.stop()
            let input=engine.inputNode
            try input.setVoiceProcessingEnabled(true)
            let format=input.outputFormat(forBus:0)
            guard format.sampleRate>0,format.channelCount>0,
                  let target=AVAudioFormat(standardFormatWithSampleRate:16000,channels:1),
                  let converter=AVAudioConverter(from:format,to:target) else {throw VoiceError.service("没有可用的麦克风")}
            input.installTap(onBus:0,bufferSize:1024,format:format){[weak self] buffer,_ in
                let capacity=AVAudioFrameCount(ceil(Double(buffer.frameLength)*16000/format.sampleRate)+32)
                guard let output=AVAudioPCMBuffer(pcmFormat:target,frameCapacity:capacity) else {return}
                var supplied=false;var error:NSError?
                converter.convert(to:output,error:&error){_,status in
                    if supplied {status.pointee = .noDataNow;return nil}
                    supplied=true;status.pointee = .haveData;return buffer
                }
                guard error==nil,let channel=output.floatChannelData?[0] else {return}
                let samples=Array(UnsafeBufferPointer(start:channel,count:Int(output.frameLength)))
                Task {@MainActor [weak self] in self?.onSamples?(samples)}
            }
            tapped=true
        }
        if !engine.isRunning {try engine.start()}
        if !player.isPlaying {player.play()}
        if meterTimer==nil {
            meterTimer=Timer.scheduledTimer(withTimeInterval:0.04,repeats:true){[weak self] _ in Task {@MainActor in self?.updateMeter()}}
        }
    }
    func enqueue(_ data:Data) throws {
        guard data.count%2==0 else {throw VoiceError.malformed}
        let count=data.count/2
        guard count>0,queuedSeconds<18,let buffer=AVAudioPCMBuffer(pcmFormat:playbackFormat,frameCapacity:AVAudioFrameCount(count)),let channel=buffer.floatChannelData?[0] else {throw VoiceError.service("播放缓冲已满")}
        buffer.frameLength=AVAudioFrameCount(count)
        // The player clock keeps advancing during network gaps. Anchor new
        // buffers at its current position rather than assuming gapless delivery.
        if let render=player.lastRenderTime,let time=player.playerTime(forNodeTime:render) {
            queuedFrames=max(queuedFrames,time.sampleTime)
            playedFrames=max(playedFrames,time.sampleTime)
        }
        let bytes=[UInt8](data)
        for i in 0..<count {channel[i]=Float(Int16(bitPattern:UInt16(bytes[2*i]) | UInt16(bytes[2*i+1])<<8))/32768}
        // Meter in 40-ms blocks against the player's sample clock, not the
        // synthesis clock (which can run many times faster than playback).
        for offset in stride(from:0,to:count,by:960) {
            let n=min(960,count-offset);var power:Float=0
            for j in offset..<(offset+n) {power += channel[j]*channel[j]}
            envelopes.append((queuedFrames+Int64(offset),min(1,sqrt(power/Float(n))*7)))
        }
        queuedFrames += Int64(count)
        player.scheduleBuffer(buffer)
        if !player.isPlaying {player.play()}
    }
    func mark(_ completion:@escaping @MainActor ()->Void) {
        guard let marker=AVAudioPCMBuffer(pcmFormat:playbackFormat,frameCapacity:1) else{return}
        marker.frameLength=1;marker.floatChannelData?[0][0]=0
        let current=epoch,end=queuedFrames;queuedFrames += 1
        pendingMarkers += 1
        player.scheduleBuffer(marker,completionCallbackType:.dataPlayedBack){[weak self] _ in
            Task {@MainActor in
                guard let self,self.epoch==current else{return}
                self.playedFrames=max(self.playedFrames,end);self.pendingMarkers -= 1;completion()
            }
        }
    }
    private func updateMeter() {
        guard let render=player.lastRenderTime,let time=player.playerTime(forNodeTime:render) else{onLevel?(0);return}
        let sample=time.sampleTime
        playedFrames=min(queuedFrames,max(playedFrames,sample))
        while envelopes.count>1 && envelopes[1].0<=sample {envelopes.removeFirst()}
        onLevel?(sample<queuedFrames && sample >= (envelopes.first?.0 ?? Int64.max) ? envelopes.first?.1 ?? 0:0)
    }
    func interrupt(){epoch += 1;player.stop();queuedFrames=0;playedFrames=0;pendingMarkers=0;envelopes=[];onLevel?(0);if engine.isRunning {player.play()}}
    func stop(){interrupt();if tapped {engine.inputNode.removeTap(onBus:0);tapped=false};engine.stop();meterTimer?.invalidate();meterTimer=nil}
    static func fixture16k(_ url:URL)throws->[Float] {
        let file=try AVAudioFile(forReading:url)
        guard file.length<24_000*30,let input=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:AVAudioFrameCount(file.length)),let target=AVAudioFormat(standardFormatWithSampleRate:16000,channels:1),let converter=AVAudioConverter(from:file.processingFormat,to:target),let output=AVAudioPCMBuffer(pcmFormat:target,frameCapacity:AVAudioFrameCount(Double(file.length)*16000/file.processingFormat.sampleRate)+64) else{throw VoiceError.malformed}
        try file.read(into:input);var supplied=false,error:NSError?
        converter.convert(to:output,error:&error){_,status in if supplied {status.pointee = .endOfStream;return nil};supplied=true;status.pointee = .haveData;return input}
        if let error {throw error}
        guard let channel=output.floatChannelData?[0] else{throw VoiceError.malformed}
        return Array(UnsafeBufferPointer(start:channel,count:Int(output.frameLength)))
    }
}
