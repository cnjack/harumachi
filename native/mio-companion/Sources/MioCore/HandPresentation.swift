import Foundation

/// Turn through an edge-on, closed-finger pose before changing the drawing.
/// Only one source drawing is visible; the common forearm never fades.
public struct HandPresentation {
    public static let variants = ["relaxed","palm","back","inward","fist","chin"]
    public let index: Int
    public let width: Float
    public let length: Float
    public var variant: String { Self.variants[index] }
    public init(motion: PuppetMotion, left: Bool) {
        let w = left ? motion.leftHand : motion.rightHand
        let weights = [w.x,w.y,w.z,w.w,left ? motion.leftFist : motion.rightFist,left ? 0 : motion.rightChin]
        let dominant = weights.indices.max { weights[$0] < weights[$1] }!
        let intermediate = weights[4]+weights[5] > 0.0001 ? 4 : 3
        let openness = PuppetMotion.smooth(0.8,1,weights[dominant])
        index = weights[dominant] < 0.8 ? intermediate : dominant
        let reach: [Float] = [73,68,68,62,38,95]
        let halfWidth: [Float] = [20,34,34,20,20,40]
        let widthRatio = halfWidth[intermediate]/halfWidth[index]
        let lengthRatio = reach[intermediate]/reach[index]
        width = widthRatio+(1-widthRatio)*openness
        length = lengthRatio+(1-lengthRatio)*openness
    }
    public func point(_ p: SIMD2<Float>, elbow: SIMD2<Float>, wrist: SIMD2<Float>) -> SIMD2<Float> {
        let axis = wrist-elbow
        let direction = axis / sqrt(axis.x*axis.x+axis.y*axis.y)
        let normal = SIMD2(-direction.y,direction.x)
        let delta = p-wrist
        let along = delta.x*direction.x+delta.y*direction.y
        let across = delta.x*normal.x+delta.y*normal.y
        let influence = PuppetMotion.smooth(0,16,along)
        let x = max(0,min(1,along/16))
        // Integrate the local longitudinal scale. Multiplying distance by a
        // changing scale folds the wrist where the scale decreases quickly.
        let integral = 16*(x*x*x-0.5*x*x*x*x)+max(0,along-16)
        return wrist+direction*(along-(1-length)*integral)
            + normal*(across*(1+(width-1)*influence))
    }
}
