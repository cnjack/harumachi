import Foundation
import Metal
import MioCore

/// Checks source keyforms and the same physics3 consumed by native and web.
/// No system monitoring, audio, network or window is started.
enum HairReview {
    static func run(at directory: URL) throws {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        guard let device=MTLCreateSystemDefaultDevice() else { throw MioRenderer.RenderError.unavailable }
        let runtime=try ProcessInfo.processInfo.environment["MIO_HAIR_FIXTURE"].map { URL(fileURLWithPath:$0) } ?? MioResources.directory("MioCubism")
        let renderer=try MioRenderer(device:device,manifest:runtime.appendingPathComponent("Mio.model3.json")),core=renderer.cubism!.model
        var referenceRenderer: MioRenderer?
        if let reference=ProcessInfo.processInfo.environment["MIO_HAIR_REFERENCE"] {
            let before=try MioRenderer(device:device,manifest:URL(fileURLWithPath:reference).appendingPathComponent("Mio.model3.json"))
            before.cubism!.reviewParameters=["ParamAngleX":0,"ParamAngleY":0,"ParamHairFront":0,"ParamHairSideL":0,"ParamHairSideR":0]
            try before.snapshot(to:directory.appendingPathComponent("reference.png"),pose:RigPose(time:0,gesture:.idle))
            referenceRenderer=before
            try FileManager.default.createDirectory(at:directory.appendingPathComponent("reference-flow"),withIntermediateDirectories:true)
        }
        let catalog=try JSONDecoder().decode(CubismRigGeometry.self,from:Data(contentsOf:runtime.appendingPathComponent("Mio.bindings.json")))
        try core.update([:]);let neutral=Dictionary(uniqueKeysWithValues:try core.meshes().map {($0.id,$0)})
        var maximumGap: Float=0,states=0,inversions=0
        for yaw: Float in [-30,0,30] { for pitch: Float in [-30,0,30] { for common: Float in [-1,0,1] {
            for l: Float in [-1,0,1] { for r: Float in [-1,0,1] {
                let values=["ParamAngleX":yaw,"ParamAngleY":pitch,"ParamHairFront":common,"ParamHairSideL":l,"ParamHairSideR":r]
                try core.update(values);let meshes=Dictionary(uniqueKeysWithValues:try core.meshes().map {($0.id,$0)})
                let crown=meshes["hair_front"]!
                for (side,x) in [("left",Float(370)),("right",Float(230))] {
                    guard let mesh=meshes["hair_front_"+side],let source=neutral[mesh.id] else { throw CubismModel.Failure(message:"Missing side hair") }
                    guard mesh.positions.allSatisfy(\.isFinite) else { throw CubismModel.Failure(message:"Nonfinite hair mesh") }
                    for y: Float in [196,197,198] {
                        let d=try catalog.point(SIMD2(x,y),mesh:mesh)-catalog.point(SIMD2(x,y),mesh:crown)
                        maximumGap=max(maximumGap,sqrt(d.x*d.x+d.y*d.y))
                    }
                    for i in stride(from:0,to:mesh.indices.count,by:3) {
                        func area(_ p: [Float]) -> Float {
                            let a=Int(mesh.indices[i])*2,b=Int(mesh.indices[i+1])*2,c=Int(mesh.indices[i+2])*2
                            return (p[b]-p[a])*(p[c+1]-p[a+1])-(p[b+1]-p[a+1])*(p[c]-p[a])
                        }
                        if area(source.positions)*area(mesh.positions)<0 { inversions+=1 }
                    }
                }
                if yaw == 0 && pitch == 0 && common == 0 {
                    renderer.cubism!.reviewParameters=values
                    try renderer.snapshot(to:directory.appendingPathComponent("tips-\(Int(l))-\(Int(r)).png"),pose:RigPose(time:0,gesture:.idle))
                }
                states+=1
            } }
        } } }
        renderer.cubism!.reviewParameters=nil
        var physics=try CubismPhysics(data:Data(contentsOf:runtime.appendingPathComponent("Mio.physics3.json")),parameters:core.parameters)
        var dynamic: [[String:Any]]=[],maximumDifference: Float=0
        for frame in 0..<1200 {
            let t=Double(frame)/60
            let yaw: Float=frame<600 ? 20*Float(sin(t*2.4)):0
            let roll: Float=frame<600 ? 9*Float(sin(t*1.9)):0
            let values=physics.update(["ParamAngleX":yaw,"ParamAngleZ":roll],time:t)
            maximumDifference=max(maximumDifference,abs((values["ParamHairSideL"] ?? 0)-(values["ParamHairSideR"] ?? 0)))
            renderer.cubism!.reviewParameters=values
            try renderer.snapshot(to:directory.appendingPathComponent(String(format:"flow-%04d.png",frame)),pose:RigPose(time:t,gesture:.idle))
            if let before=referenceRenderer {
                before.cubism!.reviewParameters=values
                try before.snapshot(to:directory.appendingPathComponent(String(format:"reference-flow/%04d.png",frame)),pose:RigPose(time:t,gesture:.idle))
            }
            let meshes=Dictionary(uniqueKeysWithValues:try core.meshes().map {($0.id,$0)})
            let roots=try [("left",Float(370)),("right",Float(230))].map { side,x -> [Float] in
                let p=try catalog.point(SIMD2(x,197),mesh:meshes["hair_front_"+side]!)
                return [p.x,p.y]
            }
            dynamic.append(["t":t,"parameters":values,"roots":roots])
        }
        let last=dynamic.last!["parameters"] as! [String:Float]
        let residual=max(abs(last["ParamHairSideL"] ?? 1),abs(last["ParamHairSideR"] ?? 1))
        let report: [String:Any]=["sourceStates":states,"maximumRootGap":maximumGap,"inversions":inversions,
            "metalFrames":1209,"physicsFrames":1200,"maximumSideDifference":maximumDifference,"settledResidual":residual,
            "dynamic":dynamic,"audioEnabled":false,"systemMonitoringStarted":false,"networkRequests":0]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("hair-review.json"))
        guard maximumGap<0.001,inversions == 0,maximumDifference>0.01,residual<0.005 else { throw CubismModel.Failure(message:"Hair source or physics check failed") }
        print("Hair: \(states) source states, \(1209) Metal frames; root gap \(maximumGap), residual \(residual)")
    }
}
