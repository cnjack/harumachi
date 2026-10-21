import Foundation

/// Native companion's fixed-step secondary motion. The same input/output IDs
/// are exported in physics3 for a web player's official Cubism physics solver.
public struct HairPhysics {
    private var time: Double?
    private var lastInput: Float = 0
    private var offset = SIMD2<Float>.zero
    private var velocity = SIMD2<Float>.zero
    public init() {}
    public mutating func update(_ values: [String:Float],time now: Double) -> [String:Float] {
        var result = values
        let input = (values["ParamAngleX"] ?? 0)/30*0.6 + (values["ParamAngleZ"] ?? 0)/12*0.4 +
            (values["ParamBodyAngleZ"] ?? 0)/3*0.2
        if let time,now >= time,now-time < 0.3 {
            let dt = Float(now-time)
            if dt > 0 {
                let impulse = -(input-lastInput)*5
                velocity += SIMD2(impulse,impulse*0.7)
                let steps = max(1,Int(ceil(dt*120))),h = dt/Float(steps)
                for _ in 0..<steps {
                    let force = -offset*SIMD2<Float>(100,58)-velocity*SIMD2<Float>(12,9)
                    velocity += force*h;offset += velocity*h
                }
            }
        } else { offset = .zero;velocity = .zero }
        self.time = now;lastInput = input
        result["ParamHairFront"] = max(-1,min(1,offset.x+input*0.12))
        result["ParamHairBack"] = max(-1,min(1,offset.y+input*0.08))
        return result
    }
}
