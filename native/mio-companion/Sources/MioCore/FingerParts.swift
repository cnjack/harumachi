import Foundation

/// Registered palm drawing, in the character's unrotated source coordinates.
/// Each whole finger stays a single component, as in AstraLayering's hand plan.
public enum FingerParts {
    public static let names=["thumb","index","middle","ring","little"]
    private static let roots: [SIMD2<Float>] = [SIMD2(575,751),SIMD2(589,808),SIMD2(564,821),SIMD2(541,831),SIMD2(516,830)]
    private static let tips: [SIMD2<Float>] = [SIMD2(624,759),SIMD2(638,864),SIMD2(602,897),SIMD2(570,906),SIMD2(524,894)]
    private static func world(_ p: SIMD2<Float>,left: Bool) -> SIMD2<Float> {
        let q=SIMD2(316+p.x/3,260+p.y/3)
        return SIMD2(left ? 600-q.x:q.x,q.y)
    }
    public static func root(_ index: Int,left: Bool) -> SIMD2<Float> { world(roots[index],left:left) }
    public static func tip(_ index: Int,left: Bool) -> SIMD2<Float> { world(tips[index],left:left) }
    public static func owner(_ p: SIMD2<Float>,left: Bool) -> Int? {
        var best: (Int,Float)?
        for i in names.indices {
            let r=root(i,left:left),t=tip(i,left:left),axis=t-r,length=sqrt(axis.x*axis.x+axis.y*axis.y),d=axis/length,q=p-r
            let along=q.x*d.x+q.y*d.y,across=abs(q.x*d.y-q.y*d.x)
            if along >= -1 && along <= length+6 && across<7.5 {
                if best == nil || across<best!.1 { best=(i,across) }
            }
        }
        return best?.0
    }
    public static func rootOverlap(_ p: SIMD2<Float>,index: Int,left: Bool) -> Bool {
        let r=root(index,left:left),t=tip(index,left:left),axis=t-r,d=axis/sqrt(axis.x*axis.x+axis.y*axis.y),q=p-r
        return q.x*d.x+q.y*d.y<1.7
    }
    public static func point(_ p: SIMD2<Float>,index: Int,left: Bool,spread: Float) -> SIMD2<Float> {
        let r=root(index,left:left),axis=tip(index,left:left)-r,d=axis/sqrt(axis.x*axis.x+axis.y*axis.y),q=p-r
        let influence=PuppetMotion.smooth(0,3,q.x*d.x+q.y*d.y)
        let angles: [Float]=[-0.09,-0.055,-0.012,0.04,0.09]
        return PuppetMotion.rotate(p,around:r,by:angles[index]*spread*(left ? -1:1)*influence)
    }
    public static func rect(_ index: Int,left: Bool) -> [Float] {
        let r=root(index,left:left),t=tip(index,left:left)
        let x=min(r.x,t.x)-10,y=min(r.y,t.y)-10
        return [x,y,abs(r.x-t.x)+20,abs(r.y-t.y)+20]
    }
}
