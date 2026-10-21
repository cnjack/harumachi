import Foundation

/// Keyform authoring shared with the editable Cubism source. These functions
/// run at export time; the renderer receives already-deformed Core meshes.
public enum FaceRig {
    /// Tiny local shifts within the original eye drawing. Neutral values are
    /// the exact source artwork, including its iris, lashes and eyebrows.
    public static func sourceEye(_ p: SIMD2<Float>,side: String,closed: Bool,open: Float,gaze: SIMD2<Float>,brow: Float) -> SIMD2<Float> {
        let cx: Float = side == "left" ? 323 : 277
        var q = p
        let browWeight = 1-PuppetMotion.smooth(196,200,p.y)
        q.y -= brow*0.8*browWeight
        if closed { return q }
        let nx = (p.x-cx)/12,ny = (p.y-210)/10
        let weight = pow(max(0,1-nx*nx),2)*pow(max(0,1-ny*ny),2)
        q += SIMD2(gaze.x*0.75,gaze.y*0.35)*weight
        // Close around the original lash line; eyebrows stay in place.
        let lid = PuppetMotion.smooth(196.5,198,p.y)
        q.y = 211+(q.y-211)*(1-(1-max(0,min(1,open)))*lid)
        return q
    }
    public static func attention(_ time: Double) -> SIMD2<Float> {
        let t = Float(time.truncatingRemainder(dividingBy:12))
        let keys: [(Float,SIMD2<Float>)] = [
            (0,.zero),(1.7,.zero),(2.05,SIMD2(-0.32,0.08)),(3.6,SIMD2(-0.32,0.08)),
            (4.1,.zero),(6.6,.zero),(7.0,SIMD2(0.38,-0.13)),(9.0,SIMD2(0.38,-0.13)),(9.6,.zero),(12,.zero)]
        for i in 1..<keys.count where t <= keys[i].0 {
            let (a,p) = keys[i-1],(b,q) = keys[i]
            return p+(q-p)*PuppetMotion.smooth(a,b,t)
        }
        return .zero
    }
    public static func blink(_ time: Double) -> Float {
        let t = Float(time.truncatingRemainder(dividingBy:12))
        func pulse(_ center: Float) -> Float {
            if t < center { return PuppetMotion.smooth(center-0.075,center,t) }
            return 1-PuppetMotion.smooth(center,center+0.13,t)
        }
        return max(pulse(4.25),pulse(9.1),pulse(9.47))
    }
}
