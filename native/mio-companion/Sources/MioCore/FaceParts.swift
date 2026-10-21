import Foundation

/// Native PSD import decomposition of the approved artwork. These are component
/// ownership regions, not new facial drawings. Every visible source pixel has
/// one owner; the sclera/cavity continue beneath the opaque foreground parts.
public enum FaceParts {
    public static func eyeOwner(x: Float,y: Float,r: UInt8 = 255,g: UInt8 = 255,b: UInt8 = 255) -> String {
        if y < 48 { return "brow" }
        let right=x<191,cx: Float=right ? 93:296,cy: Float=right ? 105:102
        let rx: Float=right ? 35:36,ry: Float=right ? 38:36
        let dx=x-cx,top: Float=(right ? 72:68)+0.006*dx*dx
        if y < top { return "upper" }
        let bottom: Float=(right ? 141:138)-0.006*dx*dx
        if y > bottom { return "lower" }
        if pow(dx/rx,2)+pow((y-cy)/ry,2)<1.04 { return "iris" }
        // Outer lashes and the fine lower outline belong to the eyelids, never
        // to the aperture that serves as the moving iris's clipping mask.
        if r<230 && g<180 && b<170 { return y<cy+8 ? "upper":"lower" }
        return "sclera"
    }
    public static func mouthOwner(x: Float,y: Float,r: UInt8,g: UInt8,b: UInt8,open: Bool) -> String {
        if !open {
            let boundary: Float=4+15*sin(.pi*min(1,max(0,x/175)))
            return y<boundary+3 ? "lip_upper":"lip_lower"
        }
        if y<24 && r>180 && g>170 && b>160 { return "teeth" }
        if y<9+0.0013*pow(x-76,2) { return "lip_upper" }
        if y>82-0.008*pow(x-76,2) { return "lip_lower" }
        if y>30 && r>170 && g>65 { return "tongue" }
        return "cavity"
    }
    public static func eyePoint(_ p: SIMD2<Float>,side: String,part: String,open: Float,gaze: SIMD2<Float>,brow: Float,angle: Float,smile: Float = 0) -> SIMD2<Float> {
        if part == "brow" {
            let cx: Float=side == "left" ? 323:277
            let inner=max(-1,min(1,(p.x-cx)/12))*(side == "left" ? -1:1)
            return p-SIMD2(0,brow*2.4+angle*2.4*inner)
        }
        if part == "iris" { return p+SIMD2(gaze.x*1.2,gaze.y*0.65) }
        if part == "closed" {
            // The source closed drawing is a smiling arc. A neutral blink meets
            // the closing aperture with a flatter lid, while smile keeps the
            // original arc. Translate along y by x, never mirror the mesh.
            let cx: Float=side == "left" ? 323:277
            let center=max(0,1-pow((p.x-cx)/14,2))
            return p+SIMD2(0,3*(1-smile)*center)
        }
        let aperture=max(0,min(1.12,open)),cx: Float=side == "left" ? 323:277
        let lift=smile*2*PuppetMotion.smooth(208,218,p.y)*max(0,1-pow((p.x-cx)/20,2))*aperture
        return SIMD2(p.x,211+(p.y-211)*aperture-lift)
    }
    public static func mouthPoint(_ p: SIMD2<Float>,form: Float,round: Float,open: Float?,part: String) -> SIMD2<Float> {
        var q=p
        let x=(p.x-300)/13.248
        q.x=300+(p.x-300)*(1+0.12*form)*(1-0.65*round)
        if let open {
            q.y-=form*2.2*min(1,x*x)
            q.y=240+(q.y-240)*open*(1+0.7*round)
        } else {
            // The approved neutral smile stays exact. Negative form flattens
            // the painted lip before lowering the corners into a mild frown.
            q.y=242+(p.y-242)*(1+min(0,form)*0.65)
            q.y-=form*(form<0 ? 5:2.2)*min(1,x*x)
        }
        return q
    }
}
