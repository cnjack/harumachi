import Foundation

/// Keyform authoring shared with the editable Cubism source. These functions
/// run at export time; the renderer receives already-deformed Core meshes.
public enum FaceRig {
    public static func turn(_ p: SIMD2<Float>, x: Float, y: Float, group: String) -> SIMD2<Float> {
        let yaw = x * .pi / 180 * 0.65, pitch = y * .pi / 180 * 0.45
        let dx = p.x-300, dy = p.y-205
        let chinWeight = 1-PuppetMotion.smooth(245,268,p.y)
        let curvature = sqrt(max(0,1-pow(dx/78,2)))
        let depth: Float = (group == "hair_back" ? -16 : (group == "hair_front" ? 20 : 29))*curvature*chinWeight
        // Different depth across the face yields genuine foreshortening. The
        // chin contact anchor remains fixed for the authored thinking pose.
        return SIMD2(300+dx*cos(yaw)+depth*sin(yaw),
                     205+dy*(1-(1-cos(pitch))*chinWeight)-depth*sin(pitch))
    }
    public static func eye(_ p: SIMD2<Float>,side: String,kind: String,open: Float,gaze: SIMD2<Float>,brow: Float) -> SIMD2<Float> {
        let cx: Float = side == "left" ? 273 : 327
        var q = p
        if kind == "brow" { q.y -= brow*2.5;return q }
        if kind == "eye_lid" { return q }
        if kind == "iris" {
            q += SIMD2(gaze.x*2.1,gaze.y*1.2)
            // Dense source grid clips the iris at the lid boundary by
            // collapsing hidden rows. No renderer-specific mask is required.
            let edge = min(1,abs((q.x-cx)/15))
            let top: Float = 202+edge*edge*3
            let bottom: Float = 218-edge*edge*2
            q.y = min(bottom,max(top,q.y))
        }
        let amount = max(0.025,min(1,open))
        q.y = 216+(q.y-216)*amount
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
