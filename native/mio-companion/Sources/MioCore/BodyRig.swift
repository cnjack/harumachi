import Foundation

/// Small authored body yaw. The neck translates as one piece, chest contours
/// gain perspective, and the lower skirt/legs remain anchored. The three keys
/// use the same interpolation as the exported Cubism source.
public enum BodyRig {
    /// Tailor the cardigan's outer panels in source keyforms. Leave the neck,
    /// shoulder attachment and central blouse at their original coordinates.
    public static func fittedCardigan(_ p: SIMD2<Float>) -> SIMD2<Float> {
        let dx=p.x-300
        let inset=4*PuppetMotion.smooth(44,95,abs(dx))*PuppetMotion.smooth(330,380,p.y)
        return p-SIMD2(dx<0 ? -inset:inset,0)
    }

    /// Reduce loose sleeve fabric across the bone, never along it. Unchanged
    /// bands at each joint keep the approved shoulder/elbow/cuff overlaps.
    /// Call only for painted sleeves; forearm skin and hands are excluded.
    public static func fittedSleeve(_ p: SIMD2<Float>,shoulder: SIMD2<Float>,elbow: SIMD2<Float>,wrist: SIMD2<Float>,upper: Bool) -> SIMD2<Float> {
        let start=upper ? shoulder:elbow,axis=upper ? elbow-shoulder:wrist-elbow
        let direction=axis/sqrt(axis.x*axis.x+axis.y*axis.y),normal=SIMD2(-direction.y,direction.x)
        let delta=p-start,along=delta.x*direction.x+delta.y*direction.y,across=delta.x*normal.x+delta.y*normal.y
        let fabric=upper ? PuppetMotion.smooth(20,38,along)*(1-PuppetMotion.smooth(82,98,along))
            : PuppetMotion.smooth(12,22,along)*(1-PuppetMotion.smooth(32,42,along))
        return p-normal*(across*0.06*fabric)
    }

    /// Source-only tailoring of the skirt, before motion keyforms are baked.
    /// This ArtMesh also contains legs: preserve the waistband and return to
    /// the original coordinates at its y=690 mesh row above the visible knees.
    public static func fittedSkirt(_ p: SIMD2<Float>) -> SIMD2<Float> {
        let hem = PuppetMotion.smooth(450,620,p.y)
            * (1-PuppetMotion.smooth(671.75,690,p.y))
        return SIMD2(300+(p.x-300)*(1-0.06*hem),p.y)
    }

    public static func turn(_ p: SIMD2<Float>, yaw: Float) -> SIMD2<Float> {
        let amount=min(1,abs(yaw)/10),a: Float=(yaw<0 ? -10:10) * .pi / 180
        let chest=PuppetMotion.smooth(310,345,p.y)
        let support=1-PuppetMotion.smooth(410,650,p.y)
        let dx=p.x-300,depth=12+(36*max(0,1-pow(dx/100,2))-12)*chest
        return p+SIMD2(amount*support*((cos(a)-1)*dx*chest+sin(a)*depth),0)
    }
    public static func shoulderOffset(left: Bool,yaw: Float) -> SIMD2<Float> {
        let p=SIMD2<Float>(left ? 231:369,320)
        return turn(p,yaw:yaw)-p
    }
    public static func follow(headYaw: Float) -> Float { max(-30,min(30,headYaw))*0.2 }
}
