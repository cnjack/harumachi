import Foundation
import Metal
import MioCore

/// Cross-product of face, gesture, gaze and blink. Samples the real Core meshes
/// and saves selected Metal frames, without starting monitors or a network client.
enum ExpressionStressReview {
    static func run(at directory: URL) throws {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        guard let device=MTLCreateSystemDefaultDevice() else { throw MioRenderer.RenderError.unavailable }
        let renderer=try MioRenderer(device:device),core=renderer.cubism!.model
        let original=try core.meshes(),catalog=try JSONDecoder().decode(CubismRigGeometry.self,from:Data(contentsOf:MioResources.directory("MioCubism").appendingPathComponent("Mio.bindings.json")))
        let neutral=Dictionary(uniqueKeysWithValues:original.map {($0.id,$0)})
        var frames=0,snapshots=0,maximumGap: Float=0,inverted: [String:Int]=[:],minimumArea: Float=Float.greatestFiniteMagnitude
        var failures: [String]=[],records: [[String:Any]]=[]
        let gestures: [CharacterGesture]=[.idle,.wave,.think,.talk,.encourage]
        let looks: [(Float,Float)]=[(-1,-1),(0,0),(1,1)]
        let clocks=[1.0,4.20,4.25]
        for style in ExpressionStyle.allCases { for intensity in ExpressionIntensity.allCases { for gesture in gestures {
            for phase in [0.3,2.2,4.9] { for (lookIndex,look) in looks.enumerated() { for (blinkIndex,clock) in clocks.enumerated() {
                var pose=RigPose(time:clock,lookX:look.0,lookY:look.1,speaking:gesture == .talk,gesture:gesture,gestureTime:phase)
                pose.expression=EmotionalExpression(style:style,intensity:intensity)
                let motion=PuppetMotion(pose:pose)
                var mixer=EmotionPlayback()
                let values=mixer.apply(CubismParameters.values(pose:pose,motion:motion),expression:pose.expression!,time:clock,mouthOwned:pose.speaking)
                try core.update(values)
                let meshes=try core.meshes(),byID=Dictionary(uniqueKeysWithValues:meshes.map {($0.id,$0)})
                let name="\(style.rawValue)-\(intensity.rawValue)-\(gesture.rawValue)-\(phase)-\(lookIndex)-\(blinkIndex)"
                for mesh in meshes {
                    if !mesh.positions.allSatisfy(\.isFinite) { failures.append(name+": nonfinite "+mesh.id) }
                    guard mesh.opacity>0.01,let source=neutral[mesh.id] else { continue }
                    for index in stride(from:0,to:mesh.indices.count,by:3) {
                        func area(_ p: [Float]) -> Float {
                            let a=Int(mesh.indices[index])*2,b=Int(mesh.indices[index+1])*2,c=Int(mesh.indices[index+2])*2
                            return (p[b]-p[a])*(p[c+1]-p[a+1])-(p[b+1]-p[a+1])*(p[c]-p[a])
                        }
                        let before=area(source.positions),after=area(mesh.positions)
                        minimumArea=min(minimumArea,abs(after))
                        if before*after < -0.001 { inverted[mesh.id,default:0]+=1 }
                    }
                }
                for side in ["left","right"] {
                    let hands=meshes.filter {$0.id.hasPrefix("hand_"+side) && $0.opacity>0.001}
                    if hands.count != 1 { failures.append(name+": hand count "+side) }
                    let left=side == "left",e=SIMD2<Float>(left ? 173:427,418),w=SIMD2<Float>(left ? 114:486,508)
                    if let arm=byID["arm_"+side],let sleeve=byID["lower_sleeve_"+side],let forearm=byID["forearm_"+side],let hand=hands.first {
                        for (a,b,p) in [(arm,sleeve,e),(forearm,hand,w)] {
                            let x=try catalog.point(p,mesh:a),y=try catalog.point(p,mesh:b),d=x-y
                            let gap=sqrt(d.x*d.x+d.y*d.y);maximumGap=max(maximumGap,gap)
                            if gap>0.01 { failures.append(name+": attachment "+side) }
                        }
                    }
                }
                if intensity == .strong && phase == 2.2 {
                    // Reset time for a direct source-pose preview, not a blend
                    // from the prior matrix cell. The normal player is unchanged.
                    let isolated=try MioRenderer(device:device)
                    try isolated.snapshot(to:directory.appendingPathComponent(name+".png"),pose:pose,motion:motion)
                    snapshots+=1
                    records.append(["file":name+".png","style":style.rawValue,"gesture":gesture.rawValue,"look":lookIndex,"blink":blinkIndex])
                }
                frames+=1
            } } }
        } } }
        let result: [String:Any]=["coreFrames":frames,"metalSnapshots":snapshots,"maximumAttachmentGap":maximumGap,"invertedTriangleOccurrences":inverted,"minimumTriangleArea":minimumArea,"failures":failures,"snapshots":records,"networkRequests":0,"systemMonitoringStarted":false,"audioEnabled":false]
        try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("expression-stress.json"))
        guard failures.isEmpty && inverted.isEmpty else { throw CubismModel.Failure(message:"Expression stress failures: \(failures.count), inverted meshes: \(inverted)") }
        print("Expression matrix: \(frames) Core states, \(snapshots) Metal snapshots; inverted triangles: \(inverted)")
    }
}
