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
    /// Authored 3 x 3 yaw/pitch surface. All landmarks, including the chin,
    /// participate; neutral is exactly the original artwork. Interpolation here
    /// matches the exported keyforms for fingertip contact and neck attachment.
    public static func turn(_ p: SIMD2<Float>,x: Float,y: Float,group: String = "face") -> SIMD2<Float> {
        func key(_ yaw: Float,_ pitch: Float) -> SIMD2<Float> {
            let a = yaw/30*0.50,b = pitch/30*0.10
            let dx=p.x-300,dy=p.y-214
            let shape=max(0,1-pow(dx/78,2)-pow(dy/88,2))
            let depth: Float = group == "hair_back" ? -7 : (group == "hair_front" ? 9:14)
            let z=depth*sqrt(shape)
            // A finite-slope facial surface gives the near/far eyes different
            // widths and moves the nose/chin relative to the cheek outline.
            // A spherical silhouette has an infinite edge slope and folds
            // the 2D mesh at larger yaw; this shallow paraboloid stays ordered.
            let yawDepth: Float = group == "hair_back" ? -12 : (group == "hair_front" ? 38:50)
            let yawZ=yawDepth*max(0,1-pow(dx/90,2))*max(0,1-pow(dy/105,2))
            return SIMD2(300+dx*cos(a)+yawZ*sin(a),214+dy*cos(b)-z*sin(b))
        }
        let u=min(1,abs(x)/30),v=min(1,abs(y)/30)
        let sx: Float=x<0 ? -30:30,sy: Float=y<0 ? -30:30
        return key(0,0)*(1-u)*(1-v)+key(sx,0)*u*(1-v)+key(0,sy)*(1-u)*v+key(sx,sy)*u*v
    }
    private static func noise(_ value: Int) -> Float {
        var x=UInt32(truncatingIfNeeded:value)&*1664525&+1013904223
        x ^= x>>16;x = x&*2246822519;x ^= x>>13
        return Float(x&65535)/65535
    }
    public static func attention(_ time: Double) -> SIMD2<Float> {
        let clock=max(0,time),block=Int(clock/7),t=Float(clock.truncatingRemainder(dividingBy:7))
        let target=SIMD2((noise(block*3+5)-0.5)*0.64,(noise(block*3+8)-0.5)*0.25)
        let strength=PuppetMotion.smooth(1.7,2.2,t)*(1-PuppetMotion.smooth(5.4,6.4,t))
        return target*strength
    }
    public static func blink(_ time: Double) -> Float {
        let clock=max(0,time),block=Int(clock/6),t=Float(clock.truncatingRemainder(dividingBy:6))
        let center: Float=block == 0 ? 4.25 : (block == 1 ? 3.1:2.3+noise(block+61)*2.2)
        func pulse(_ center: Float) -> Float {
            if t < center { return PuppetMotion.smooth(center-0.075,center,t) }
            return 1-PuppetMotion.smooth(center,center+0.13,t)
        }
        return max(pulse(center),(block == 1 || noise(block+81)<0.2) ? pulse(center+0.37):0)
    }
}
