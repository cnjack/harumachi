import XCTest
@testable import MioCore

final class EmotionTests: XCTestCase {
    private var assets: URL { URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/MioApp/Resources/MioCubism") }

    func testClefChoosesFacialPerformanceAndHandMeaning() throws {
        let body = try JSONSerialization.jsonObject(with:ClefClient(configuration:.init()).requestBody(for:.init(kind:"message",summary:"完成了，一起加油！"))) as! [String:Any]
        let questions = body["questions"] as! [String:Any]
        for key in ["expression","intensity","hand"] {
            XCTAssertNotNil(questions[key], "Current Clef must choose \(key); a mood-only response cannot drive coordinated performance")
        }
    }

    func testAuthoredBrowsAndRoundMouthHaveRealCoreGeometry() throws {
        guard FileManager.default.fileExists(atPath:"/Applications/Live2D Cubism 5.3/res/libLive2DCubismCoreJNI.dylib") else { throw XCTSkip("Official Core is installed separately") }
        let model = try CubismModel(manifest:assets.appendingPathComponent("Mio.model3.json"))
        for (param,mesh) in [("ParamBrowLAngle","brow_left"),("ParamBrowRAngle","brow_right"),("ParamMouthRound","mouth_open_cavity")] {
            XCTAssertTrue(model.parameters.contains {$0.id == param}, "Semantic expression must have an authored parameter")
            try model.update(["ParamMouthOpenY":0.6]);let a = try XCTUnwrap(model.meshes().first {$0.id == mesh})
            try model.update([param:1,"ParamMouthOpenY":0.6]);let b = try XCTUnwrap(model.meshes().first {$0.id == mesh})
            XCTAssertGreaterThan(zip(a.positions,b.positions).map {abs($0-$1)}.max() ?? 0,0.5, "\(param) must deform the actual MOC, not only exist in JSON")
        }
    }

    func testSpeechAndBlinkKeepOwnershipWhileEmotionChanges() {
        var mixer=EmotionPlayback()
        var previous: [String:Float]?
        for frame in 0..<480 {
            let style: ExpressionStyle=frame<120 ? .joyful:frame<240 ? .concerned:frame<360 ? .surprised:.neutral
            let base: [String:Float] = ["ParamEyeLOpen":0,"ParamEyeROpen":0,"ParamMouthOpenY":frame%3 == 0 ? 0:0.6]
            let result=mixer.apply(base,expression:.init(style:style,intensity:.strong),time:Double(frame)/60)
            XCTAssertEqual(result["ParamMouthOpenY"],base["ParamMouthOpenY"],"Emotion cannot open the mouth during a speech pause")
            XCTAssertEqual(result["ParamEyeLOpen"],0,"Expression must not reopen a blink")
            if let previous { XCTAssertLessThan(abs(result["ParamMouthForm"]!-previous["ParamMouthForm"]!),0.16,"Changing joy to concern must not snap") }
            previous=result
        }
        XCTAssertLessThan(abs(previous!["ParamMouthForm"]!),0.001)
    }

    func testEveryExpressionTransitionKeepsAuthoredFaceGeometryContinuous() throws {
        guard FileManager.default.fileExists(atPath:"/Applications/Live2D Cubism 5.3/res/libLive2DCubismCoreJNI.dylib") else { throw XCTSkip("Official Core is installed separately") }
        let model=try CubismModel(manifest:assets.appendingPathComponent("Mio.model3.json"))
        let faceIDs=Set(try model.meshes().filter {
            $0.id.hasPrefix("eyes_") || $0.id.hasPrefix("brow_") || $0.id.hasPrefix("mouth_")
        }.map(\.id))
        var maximumStep: Float=0, frames=0
        var invalidVertices=0, invertedTriangles=0
        for from in ExpressionStyle.allCases { for to in ExpressionStyle.allCases {
            var mixer=EmotionPlayback()
            let base: [String:Float] = ["ParamEyeLOpen":1,"ParamEyeROpen":1,"ParamMouthOpenY":0.55]
            try model.update(mixer.apply(base,expression:.init(style:from,intensity:.strong),time:0))
            var previous=Dictionary(uniqueKeysWithValues:try model.meshes().filter {faceIDs.contains($0.id)}.map {($0.id,$0)})
            for frame in 1...90 {
                try model.update(mixer.apply(base,expression:.init(style:to,intensity:.strong),time:Double(frame)/60))
                let current=try model.meshes().filter {faceIDs.contains($0.id)}
                for mesh in current {
                    let prior=try XCTUnwrap(previous[mesh.id])
                    if !mesh.positions.allSatisfy(\.isFinite) { invalidVertices+=1 }
                    maximumStep=max(maximumStep,zip(mesh.positions,prior.positions).map {abs($0-$1)}.max() ?? 0)
                    guard mesh.opacity>0.01,prior.opacity>0.01 else { continue }
                    for index in stride(from:0,to:mesh.indices.count,by:3) {
                        func area(_ p: [Float]) -> Float {
                            let a=Int(mesh.indices[index])*2,b=Int(mesh.indices[index+1])*2,c=Int(mesh.indices[index+2])*2
                            return (p[b]-p[a])*(p[c+1]-p[a+1])-(p[b+1]-p[a+1])*(p[c]-p[a])
                        }
                        if area(mesh.positions)*area(prior.positions)<(-0.001) { invertedTriangles+=1 }
                    }
                }
                previous=Dictionary(uniqueKeysWithValues:current.map {($0.id,$0)});frames+=1
            }
        } }
        XCTAssertEqual(invalidVertices,0,"Expression interpolation produced a non-finite face vertex")
        XCTAssertEqual(invertedTriangles,0,"A face triangle inverted between authored expression keyforms")
        XCTAssertLessThan(maximumStep,3,"A 60 Hz expression transition must not jump between authored face shapes")
        print("All 64 expression transitions: \(frames) Core frames, maximum vertex step \(maximumStep) px")
    }

    func testDecomposedIrisDoesNotFlattenDuringBlinkAndBrowsDoNotPullEyes() throws {
        guard FileManager.default.fileExists(atPath:"/Applications/Live2D Cubism 5.3/res/libLive2DCubismCoreJNI.dylib") else { throw XCTSkip("Official Core is installed separately") }
        let model=try CubismModel(manifest:assets.appendingPathComponent("Mio.model3.json"))
        let original=try model.meshes()
        try model.update(["ParamEyeLOpen":0.4,"ParamEyeROpen":0.4,"ParamBrowLAngle":1,"ParamBrowRAngle":1])
        let blink=try model.meshes()
        for side in ["left","right"] {
            XCTAssertEqual(original.first {$0.id == "eyes_iris_"+side}?.positions,blink.first {$0.id == "eyes_iris_"+side}?.positions,"Eyelids and mask close over the iris, without squashing it")
            let iris=try XCTUnwrap(blink.first {$0.id == "eyes_iris_"+side})
            let sclera=try XCTUnwrap(blink.first {$0.id == "eyes_open_"+side})
            XCTAssertEqual(iris.masks,[sclera.sourceIndex],"Iris must be clipped to its own eye aperture")
        }
        try model.update(["ParamBrowLAngle":1,"ParamBrowRAngle":1]);let brows=try model.meshes()
        for a in original where a.id.hasPrefix("eyes_") {
            XCTAssertEqual(a.positions,brows.first {$0.id == a.id}?.positions)
        }
    }

    func testFingerComponentsKeepTheirRootsAndFollowHandVisibility() throws {
        guard FileManager.default.fileExists(atPath:"/Applications/Live2D Cubism 5.3/res/libLive2DCubismCoreJNI.dylib") else { throw XCTSkip("Official Core is installed separately") }
        let model=try CubismModel(manifest:assets.appendingPathComponent("Mio.model3.json"))
        let topology=try JSONDecoder().decode(CubismRigGeometry.self,from:Data(contentsOf:assets.appendingPathComponent("Mio.bindings.json")))
        try model.update(["ParamHandL":1,"ParamHandR":1]);let original=try model.meshes()
        XCTAssertEqual(original.filter {$0.id.hasPrefix("finger_") && $0.opacity>0.99}.count,10)
        for spread: Float in [-1,1] {
            try model.update(["ParamHandL":1,"ParamHandR":1,"ParamFingerSpreadL":spread,"ParamFingerSpreadR":spread])
            let current=try model.meshes()
            for left in [true,false] { for (index,name) in FingerParts.names.enumerated() {
                let id="finger_"+(left ? "left_":"right_")+name
                let a=try XCTUnwrap(original.first {$0.id == id}),b=try XCTUnwrap(current.first {$0.id == id})
                let x=try topology.point(FingerParts.root(index,left:left),mesh:a),y=try topology.point(FingerParts.root(index,left:left),mesh:b)
                XCTAssertLessThan(abs(x.x-y.x)+abs(x.y-y.y),0.15,"Finger root must remain attached")
                XCTAssertGreaterThan(zip(a.positions,b.positions).map {abs($0-$1)}.max() ?? 0,0.1)
            } }
        }
        try model.update(["ParamHandL":4,"ParamHandR":4])
        XCTAssertTrue(try model.meshes().filter {$0.id.hasPrefix("finger_")}.allSatisfy {$0.opacity == 0},"Fingers cannot leak through a fist drawing")
    }

    func testFingerEdgePixelsBelongToFingersNotPalm() {
        // Real residual contour pixels found in the independently exported palm.
        for p in [SIMD2<Float>(519.5,562.5),SIMD2<Float>(518.5,563.5),SIMD2<Float>(508.5,565.5)] {
            XCTAssertNotNil(FingerParts.owner(p,left:false),"A loose fingertip contour must move with its finger")
            XCTAssertNotNil(FingerParts.owner(SIMD2(600-p.x,p.y),left:true))
        }
    }

    func testModelSelectedHandsWorkForShortRepliesAndQuietWins() {
        let expected: [ExpressionHand:(CharacterGesture,Int)] = [.rest:(.idle,0),.wave:(.wave,1),.explain:(.talk,1),.chin:(.think,5),.encourage:(.encourage,4)]
        for (hand,pair) in expected {
            var pose=RigPose(time:2)
            PerformanceCue(intent:.reply,mood:.happy,text:"加油。",expression:.init(style:.determined,hand:hand)).apply(to:&pose,elapsed:2)
            XCTAssertEqual(pose.resolvedGesture,pair.0)
            XCTAssertEqual(HandPresentation(motion:PuppetMotion(pose:pose),left:false).index,pair.1)
            PerformanceCue(intent:.quiet,mood:.happy,expression:.init(style:.joyful,hand:hand)).apply(to:&pose,elapsed:2)
            XCTAssertEqual(pose.resolvedGesture,.idle);XCTAssertFalse(pose.speaking)
        }
    }

    func testManualGestureDoesNotFreezePreviousReplyExpression() {
        var pose=RigPose(time:1)
        let old=PerformanceCue(intent:.reply,mood:.concerned,text:"我在听。",expression:.init(style:.concerned,hand:.rest))
        pose.present(old,elapsed:0.5)
        XCTAssertEqual(pose.expression?.style,.concerned)
        pose.gesture = .wave;pose.gestureTime=1
        let current=PerformanceCue(intent:.reply,mood:.happy,text:"做到了，一起庆祝吧！",expression:.init(style:.joyful,hand:.encourage))
        pose.present(current,elapsed:0.5)
        XCTAssertEqual(pose.resolvedGesture,.wave,"The explicit hand motion remains selected")
        XCTAssertEqual(pose.expression?.style,.joyful,"New replies still update the face in manual mode")
        XCTAssertEqual(pose.speech?.duration,current.speech.duration,"Current text owns lip-sync even with manually selected arms")
        pose.present(current,elapsed:20)
        XCTAssertEqual(pose.expression?.style,.neutral,"A finished reply must release its expression")
        pose.gesture = .talk;pose.gestureTime=1
        pose.present(current,elapsed:20)
        XCTAssertTrue(pose.speaking,"Manual talk still demonstrates mouth motion after the reply ends")
        XCTAssertNil(pose.speech,"Manual demo uses its own timing after text ends")
        pose.present(nil,elapsed:0)
        XCTAssertNil(pose.expression,"Removing a performance cannot leave a stale face override")
    }

    func testExpressionHistoryReachesCurrentDecisionWithoutNewClassifier() throws {
        let now=Date(),event=SystemEvent(kind:"message",summary:"然后呢？",date:now)
        var memory=DialogueMemory(now:now.addingTimeInterval(-60))
        let line=try XCTUnwrap(SpeechCatalog.candidates(for:event,context:DialogueContext(now:now)).first)
        memory.recordReply(line,at:now.addingTimeInterval(-5),expression:.init(style:.curious,hand:.chin))
        let context=memory.context(for:event,events:[],now:now)
        let body=try JSONSerialization.jsonObject(with:ClefClient(configuration:.init()).requestBody(for:event,context:context)) as! [String:Any]
        let state=body["state"] as! [String:Any],encodedContext=state["context"] as! [String:Any]
        let turn=try XCTUnwrap((encodedContext["conversation"] as? [[String:Any]])?.last)
        XCTAssertEqual((turn["expression"] as? [String:String])?["hand"],"chin")
        XCTAssertEqual(body["model"] as? String,"clef-omni")
        let expired=memory.context(for:event,events:[],now:now.addingTimeInterval(1900))
        XCTAssertTrue(expired.conversation.isEmpty,"Expression history follows the same bounded session memory as dialogue")
    }

    func testSmileLidsMoveWithoutStretchingIris() throws {
        guard FileManager.default.fileExists(atPath:"/Applications/Live2D Cubism 5.3/res/libLive2DCubismCoreJNI.dylib") else { throw XCTSkip("Official Core is installed separately") }
        let model=try CubismModel(manifest:assets.appendingPathComponent("Mio.model3.json"))
        let a=try model.meshes()
        try model.update(["ParamEyeLSmile":1,"ParamEyeRSmile":1]);let b=try model.meshes()
        for side in ["left","right"] {
            XCTAssertEqual(a.first {$0.id=="eyes_iris_"+side}?.positions,b.first {$0.id=="eyes_iris_"+side}?.positions)
            let lowerA=try XCTUnwrap(a.first {$0.id=="eyes_lower_"+side}),lowerB=try XCTUnwrap(b.first {$0.id=="eyes_lower_"+side})
            XCTAssertGreaterThan(zip(lowerA.positions,lowerB.positions).map {abs($0-$1)}.max() ?? 0,0.5)
        }
    }

    func testInvalidSemanticChoicesCannotBecomeParameterCommands() throws {
        func response(_ style: String,_ confidence: String = "0.9") -> Data {
            Data("""
            {"model":"clef-omni","answers":{"mood":{"choice":"happy","confidence":0.9},"reaction":{"choice":"notice","confidence":0.9},"expression":{"choice":"\(style)","confidence":\(confidence)},"intensity":{"choice":"strong","confidence":0.9},"hand":{"choice":"encourage","confidence":0.9}}}
            """.utf8)
        }
        XCTAssertEqual(try ClefClient.decode(response("determined")).expression?.hand,.encourage)
        XCTAssertThrowsError(try ClefClient.decode(response("ParamEyeLOpen=500")))
        XCTAssertThrowsError(try ClefClient.decode(response("joyful","1.1")))
        XCTAssertEqual(try ClefClient.decode(response("joyful","0.1")).expression?.style,.neutral)
        let plurality=String(data:response("joyful"),encoding:.utf8)!.replacingOccurrences(of:"\"hand\":{\"choice\":\"encourage\",\"confidence\":0.9}",with:"\"hand\":{\"choice\":\"encourage\",\"confidence\":0.3771}")
        XCTAssertEqual(try ClefClient.decode(Data(plurality.utf8)).expression?.hand,.encourage,"Five-way choice probabilities must not use a binary confidence gate")
    }

    func testLiveClefSemanticExpressions() async throws {
        guard let base=ProcessInfo.processInfo.environment["MIO_EMOTION_LIVE"],let out=ProcessInfo.processInfo.environment["MIO_EMOTION_EVIDENCE"] else { throw XCTSkip("Opt-in synthetic Clef request") }
        let client=ClefClient(configuration:.init(baseURL:base,timeout:15)),directory=URL(fileURLWithPath:out)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        var records: [[String:Any]]=[]
        for (name,text) in [("welcome","你好呀，我回来了"),("joyful","项目做完了，终于成功啦！好开心！"),("concerned","今天很难过，有点撑不住了，陪我一会儿"),("curious","工作卡住了，可以一起想想下一步吗"),("determined","我准备再试一次，请给我打气加油"),("surprised","太意外了，我居然抽中了头等奖！"),("sleepy","好困啊，准备睡觉，晚安"),("quiet","先别说话，我忙一会儿")] {
            let event=SystemEvent(kind:"message",summary:text),context=DialogueContext(now:event.date)
            try client.requestBody(for:event,context:context).write(to:directory.appendingPathComponent(name+"-request.json"))
            let result=try await client.decide(event,context:context)
            try JSONEncoder().encode(result).write(to:directory.appendingPathComponent(name+"-decision.json"))
            XCTAssertNotNil(result.expression);XCTAssertEqual(result.source,"Clef 决策")
            records.append(["name":name,"message":text,"decision":try JSONSerialization.jsonObject(with:JSONEncoder().encode(result))])
        }
        try JSONSerialization.data(withJSONObject:records,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("decisions.json"))
    }
}
