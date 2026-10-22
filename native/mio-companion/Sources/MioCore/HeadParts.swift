import Foundation

/// Ownership in the original 302 x 318 face drawing. The ear roots extend
/// underneath the face layer; no runtime patch or alternate face is needed.
public enum HeadParts {
    public static func earEdge(_ y: Float,left: Bool) -> Float {
        left ? 274-(y-147)*0.34 : 19+(y-156)*0.36
    }
    public static func contains(_ p: SIMD2<Float>,part: String) -> Bool {
        let leftY=(149...238).contains(p.y),rightY=(161...248).contains(p.y)
        if part == "ear_left" { return leftY && p.x>=earEdge(p.y,left:true)-2 }
        if part == "ear_right" { return rightY && p.x<=earEdge(p.y,left:false)+2 }
        if part == "nose" { return noseWeight(p)>0 }
        return (!rightY || p.x>=earEdge(p.y,left:false)) && (!leftY || p.x<=earEdge(p.y,left:true))
    }
    public static func noseWeight(_ p: SIMD2<Float>) -> Float {
        let d=sqrt(pow((p.x-147.5)/7,2)+pow((p.y-223)/9,2))
        return 1-PuppetMotion.smooth(0.72,1,d)
    }
    public static func fillWeight(_ p: SIMD2<Float>) -> Float {
        let d=sqrt(pow((p.x-147.5)/13,2)+pow((p.y-223)/15,2))
        return 1-PuppetMotion.smooth(0.60,1,d)
    }
}
