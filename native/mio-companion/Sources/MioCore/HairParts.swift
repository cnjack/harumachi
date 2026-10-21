import Foundation

/// Front cap and two side locks share the approved original drawing. The split
/// sits inside an unmoving root band; only the free lower tips gain extra sway.
public enum HairParts {
    public static func contains(_ p: SIMD2<Float>,component: String) -> Bool {
        if component == "crown" { return p.y <= 198 }
        guard p.y >= 196 else { return false }
        return component == "left" ? p.x >= 300:p.x < 300
    }
    public static func point(_ p: SIMD2<Float>,sway: Float) -> SIMD2<Float> {
        let weight=pow(PuppetMotion.smooth(216,290,p.y),2)
        return p+SIMD2(2.2*sway*weight,-0.45*abs(sway)*weight)
    }
}
