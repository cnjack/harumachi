import XCTest
@testable import MioCore

final class PerformanceTests: XCTestCase {
    func testAutomaticDoesNotInventGreetingsOrThinking() {
        for second in [2.0,18,54,70,106,122] {
            let automatic = PuppetMotion(pose:RigPose(time:second))
            let resting = PuppetMotion(pose:RigPose(time:second,gesture:.idle))
            XCTAssertEqual(automatic.rightElbow,resting.rightElbow,accuracy:0.001)
            XCTAssertEqual(automatic.rightShoulder,resting.rightShoulder,accuracy:0.001)
            XCTAssertEqual(automatic.thoughtOpacity,0)
        }
    }
    func testSpeechHasClosedMouthPunctuationAndStopsAtTheEnd() {
        let speech=SpeechTimeline("你好，澪。")
        XCTAssertEqual(speech.beats.count,3)
        let pause=(speech.beats[1].end+speech.beats[2].start)/2
        XCTAssertEqual(speech.mouth(at:pause),0)
        XCTAssertGreaterThan(speech.beats[2].start-speech.beats[1].end,0.25)
        XCTAssertEqual(speech.mouth(at:speech.duration+0.1),0)
        XCTAssertGreaterThan(speech.mouth(at:(speech.beats[0].start+speech.beats[0].end)/2),0.3)
    }
    func testWelcomeCooldownAndShortReplyDoNotWave() {
        var director=PerformanceDirector();let date=Date(timeIntervalSince1970:1000)
        let event=SystemEvent(kind:"wake",summary:"",date:date)
        let decision=Decision(mood:.happy,reaction:.greet,confidence:1,source:"test")
        let welcome=director.response(decision,event:event,text:"欢迎回来。",now:date)
        XCTAssertEqual(welcome.intent,.welcome)
        XCTAssertEqual(director.response(decision,event:event,text:"嗯。",now:date.addingTimeInterval(5)).intent,.reply)
        var pose=RigPose(time:1)
        welcome.apply(to:&pose,elapsed:1);XCTAssertEqual(pose.resolvedGesture,.wave)
        welcome.apply(to:&pose,elapsed:10);XCTAssertEqual(pose.resolvedGesture,.idle)
        PerformanceCue(intent:.reply,mood:.happy,text:"嗯，我在。",at:date).apply(to:&pose,elapsed:0.5)
        XCTAssertEqual(pose.resolvedGesture,.idle)
        XCTAssertTrue(pose.speaking)
    }
    func testWaitingThenReplyAndQuietAreDistinct() {
        var pose=RigPose(time:1)
        let waiting=PerformanceCue(intent:.waiting,mood:.thinking)
        waiting.apply(to:&pose,elapsed:0.2);XCTAssertEqual(pose.resolvedGesture,.idle)
        waiting.apply(to:&pose,elapsed:4);XCTAssertEqual(pose.resolvedGesture,.think)
        XCTAssertFalse(pose.speaking)
        PerformanceCue(intent:.quiet,mood:.neutral).apply(to:&pose,elapsed:1)
        XCTAssertEqual(pose.resolvedGesture,.idle);XCTAssertFalse(pose.speaking)
    }
    func testFiveExpressionsPreserveBlinkAndNeutral() {
        let base: [String:Float] = ["ParamEyeLOpen":0,"ParamEyeROpen":0,"ParamMouthForm":0,"ParamBrowLY":0,"ParamBrowRY":0]
        XCTAssertEqual(CubismExpression.presets["neutral"]!.apply(to:base),base)
        for expression in CubismExpression.presets.values {
            let result=expression.apply(to:base)
            XCTAssertEqual(result["ParamEyeLOpen"],0);XCTAssertEqual(result["ParamEyeROpen"],0)
        }
        XCTAssertGreaterThan(CubismExpression.presets["happy"]!.apply(to:base)["ParamMouthForm"]!,0)
        XCTAssertLessThan(CubismExpression.presets["concerned"]!.apply(to:base)["ParamMouthForm"]!,0)
    }
    func testAttentionAndBlinkDoNotRepeatEveryTwelveSeconds() {
        XCTAssertNotEqual(FaceRig.attention(3),FaceRig.attention(15))
        XCTAssertNotEqual(FaceRig.blink(4.25),FaceRig.blink(16.25))
    }
    func testFinishedReplyReleasesRestingExpressionMouth() {
        let cue=PerformanceCue(intent:.reply,mood:.thinking,text:"哦！",expression:.init(style:.surprised))
        var pose=RigPose(time:0)
        cue.apply(to:&pose,elapsed:cue.speech.duration+0.1)
        // A completed speech timeline must not suppress the surprised O mouth.
        XCTAssertNil(pose.speech)
        XCTAssertEqual(pose.expression?.style,.surprised)
        cue.apply(to:&pose,elapsed:0.2)
        XCTAssertNotNil(pose.speech)
        cue.apply(to:&pose,elapsed:-0.1)
        XCTAssertNil(pose.speech)
    }

    func testManualExpressionKeepsSpeechAndHandsAndAutomaticRestoresLatestCue() {
        let cue=PerformanceCue(intent:.reply,mood:.thinking,text:"先想一想，我们一起把这件事情慢慢弄清楚。",expression:.init(style:.curious,hand:.chin))
        var pose=RigPose(time:1)
        let t=(cue.speech.beats[0].start+cue.speech.beats[0].end)/2
        for style in ExpressionStyle.allCases {
            pose.present(cue,elapsed:t,expressionOverride:style)
            XCTAssertEqual(pose.expression?.style,style)
            XCTAssertEqual(pose.expression?.hand,.chin)
            XCTAssertEqual(pose.resolvedGesture,.think)
            XCTAssertEqual(pose.mouthAmount,cue.speech.mouth(at:t),accuracy:0.001)
        }
        pose.gesture = .wave
        pose.present(cue,elapsed:t,expressionOverride:.joyful)
        XCTAssertEqual(pose.resolvedGesture,.wave)
        XCTAssertEqual(pose.expression?.style,.joyful)
        pose.present(cue,elapsed:t)
        XCTAssertEqual(pose.expression?.style,.curious)
        pose.present(cue,elapsed:100,expressionOverride:.surprised)
        XCTAssertEqual(pose.expression?.style,.surprised)
        XCTAssertNil(pose.speech)
        pose.present(cue,elapsed:100)
        XCTAssertEqual(pose.expression?.style,.neutral)
    }

}
