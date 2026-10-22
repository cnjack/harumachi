import Foundation

/// Reader for standard motion3 parameter curves: linear, cubic, step and inverse
/// step. Unrestricted Bezier curves solve time before evaluating value.
public struct CubismMotion {
    public struct Curve {
        public struct Segment { let kind: Int; let points: [SIMD2<Double>] }
        public let id: String
        let first: SIMD2<Double>
        let segments: [Segment]
        public func value(at time: Double) -> Float {
            var start=first
            for segment in segments {
                let end=segment.points.last!
                if time <= end.x {
                    if time <= start.x { return Float(start.y) }
                    let u=max(0,min(1,(time-start.x)/max(0.000001,end.x-start.x)))
                    switch segment.kind {
                    case 2: return Float(start.y)
                    case 3: return Float(end.y)
                    case 1:
                        let a=segment.points[0],b=segment.points[1]
                        func cubic(_ t: Double,_ p0: Double,_ p1: Double,_ p2: Double,_ p3: Double) -> Double {
                            let v=1-t;return v*v*v*p0+3*v*v*t*p1+3*v*t*t*p2+t*t*t*p3
                        }
                        var low=0.0,high=1.0
                        for _ in 0..<22 { let m=(low+high)/2;if cubic(m,start.x,a.x,b.x,end.x)<time { low=m } else { high=m } }
                        return Float(cubic((low+high)/2,start.y,a.y,b.y,end.y))
                    default: return Float(start.y+(end.y-start.y)*u)
                    }
                }
                start=end
            }
            return Float(start.y)
        }
    }
    public let duration: Double
    public let loop: Bool
    public let curves: [Curve]
    public init(data: Data) throws {
        guard let root=try JSONSerialization.jsonObject(with:data) as? [String:Any],
              let meta=root["Meta"] as? [String:Any],let duration=meta["Duration"] as? Double,duration>0,
              let raw=root["Curves"] as? [[String:Any]] else { throw CubismModel.Failure(message:"Invalid motion3") }
        self.duration=duration;loop=meta["Loop"] as? Bool ?? false
        curves=try raw.filter { $0["Target"] as? String == "Parameter" }.map { entry in
            guard let id=entry["Id"] as? String,let values=entry["Segments"] as? [Double],values.count>=2,values.allSatisfy(\.isFinite) else { throw CubismModel.Failure(message:"Invalid motion curve") }
            let first=SIMD2(values[0],values[1]);var cursor=2,segments: [Curve.Segment]=[]
            var previous=first.x
            while cursor<values.count {
                let kind=Int(values[cursor]),count=Int(values[cursor]) == 1 ? 3:1;cursor+=1
                guard (0...3).contains(kind),cursor+count*2<=values.count else { throw CubismModel.Failure(message:"Unsupported motion segment") }
                var points: [SIMD2<Double>] = []
                for _ in 0..<count { points.append(SIMD2(values[cursor],values[cursor+1]));cursor+=2 }
                guard points.last!.x >= previous else { throw CubismModel.Failure(message:"Motion times must increase") }
                previous=points.last!.x;segments.append(.init(kind:kind,points:points))
            }
            return Curve(id:id,first:first,segments:segments)
        }
    }
    public func sample(_ time: Double) -> [String:Float] {
        let t=loop ? max(0,time).truncatingRemainder(dividingBy:duration):max(0,min(duration,time))
        return Dictionary(uniqueKeysWithValues:curves.map { ($0.id,$0.value(at:t)) })
    }
}

public struct MotionLibrary {
    public let motions: [String:CubismMotion]
    public init(directory: URL) throws {
        var loaded: [String:CubismMotion]=[:]
        for name in ["idle","wave","think","talk","encourage"] {
            loaded[name]=try CubismMotion(data:Data(contentsOf:directory.appendingPathComponent("motions/\(name).motion3.json")))
        }
        motions=loaded
    }
    public func motion(for pose: RigPose) -> PuppetMotion {
        let gesture=pose.resolvedGesture
        guard let clip=motions[gesture.rawValue] else { return PuppetMotion(pose:pose) }
        let time=pose.resolvedTime,values=clip.sample(time)
        var m=PuppetMotion(pose:pose)
        // Held thinking contact is a runtime interaction residual. Its source
        // keyforms and authored neutral animation still come from the model.
        if gesture != .think {
            m.leftShoulder=values["ParamShoulderL"] ?? m.leftShoulder
            m.rightShoulder=values["ParamShoulderR"] ?? m.rightShoulder
            m.leftElbow=values["ParamElbowL"] ?? m.leftElbow
            m.rightElbow=values["ParamElbowR"] ?? m.rightElbow
            m.leftWrist=values["ParamWristL"] ?? m.leftWrist
            m.rightWrist=values["ParamWristR"] ?? m.rightWrist
        }
        m.torso=(values["ParamBodyAngleZ"] ?? 0)*Float.pi/180+pose.nod*0.007
        m.torsoLift=values["ParamTorsoLift"] ?? 0
        if gesture != .think {
            m.head=(values["ParamAngleZ"] ?? 0)*Float.pi/180
        }
        return m
    }
}
