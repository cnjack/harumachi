import Foundation

/// Keyform authoring shared with the editable Cubism source. These functions
/// run at export time; the renderer receives already-deformed Core meshes.
public enum FaceRig {
    /// Final source-model proportion. Keep all authored facial relationships
    /// and scale the complete head around its chin/neck attachment.
    public static let headScale: Float = 0.8
    public static func fittedHead(_ point: SIMD2<Float>,x: Float = 0,y: Float = 0) -> SIMD2<Float> {
        let anchor = turn(SIMD2<Float>(300,268),x:x,y:y)
        return anchor + (point-anchor)*headScale
    }
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
            let direction=yaw/30,amount=abs(direction),b=pitch/30*0.12
            let dx=p.x-300,dy=p.y-214
            var q=p,depth: Float=18
            if group == "hair_back" {
                // The back of the skull stays broad and travels behind the face.
                q.x=300+dx*(1+0.01*amount)-direction*2
                depth = -8
            } else if group.hasPrefix("hair_front") {
                // Crown and side locks share an identical root shape. Lower
                // locks wrap around the far cheek instead of sliding with it.
                let crown=2+6*max(0,1-pow(dx/95,2))
                let near=dx*direction<0
                let wrap: Float=near ? -1:5
                let lower=PuppetMotion.smooth(200,270,p.y)
                q.x=300+dx*(1-0.01*amount)+direction*(crown*(1-lower)+wrap*lower)
                depth=12*max(0,1-pow(dx/105,2))
            } else if group.hasPrefix("ear_") {
                let cx: Float=group == "ear_left" ? 353:247
                let near=(cx-300)*direction<0
                let scale: Float=near ? 1:0.68
                let rootScale: Float=near ? 0.94:0.90
                q.x=300+(cx-300)*(1+(rootScale-1)*amount)+(p.x-cx)*(1+(scale-1)*amount)+direction*(near ? 8:-4)
                depth = -2
            } else if group.hasPrefix("eyes_") || group.hasPrefix("brow_") {
                let cx: Float=group.hasSuffix("_left") ? 323:277
                let near=(cx-300)*direction<0
                // Preserve the round source eye. Perspective belongs to the
                // socket placement; the far eye itself is only mildly narrower.
                let scale: Float=near ? 1:0.94
                q.x=300+(cx-300)*(1-0.035*amount)+direction*11+(p.x-cx)*(1+(scale-1)*amount)
                depth=25
            } else if group == "nose" {
                q.x=300+dx*(1-0.10*amount)+direction*15
                depth=34
            } else if group.hasPrefix("mouth_") {
                q.x=300+dx*(1-0.05*amount)+direction*10
                depth=24
            } else {
                // Cheek and jaw key shape: broad near cheek, short far cheek,
                // turning chin and a stable neck attachment, not a flat oval.
                let cheek=PuppetMotion.smooth(155,209,p.y)
                let jaw=PuppetMotion.smooth(235,269,p.y)
                let center=3+9*cheek-6*jaw
                let envelope=max(0,1-pow(dx/76,2))
                q.x=300+dx*(1-0.035*amount)+direction*(3+(center-3)*envelope)
                depth=18*max(0,1-pow(dx/78,2)-pow(dy/100,2))
            }
            q.y=214+dy*cos(b)-depth*sin(b)
            return q
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
