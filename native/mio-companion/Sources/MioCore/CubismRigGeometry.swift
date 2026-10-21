import Foundation

/// QA samples the production MOC's actual vertices, with source topology
/// recorded at bake time. No arm transform is reimplemented in the checker.
public struct CubismRigGeometry: Decodable {
    struct Layout: Decodable { let id: String;let rect: [Float];let columns,rows: Int }
    let meshes: [Layout]
    public func point(_ rest: SIMD2<Float>,mesh: CubismModel.Mesh) throws -> SIMD2<Float> {
        guard let layout=meshes.first(where:{$0.id==mesh.id}),mesh.positions.count==2*(layout.columns+1)*(layout.rows+1) else {
            throw CubismModel.Failure(message:"MOC topology differs from source: \(mesh.id)")
        }
        let x=max(0,min(Float(layout.columns)-0.00001,(rest.x-layout.rect[0])/layout.rect[2]*Float(layout.columns)))
        let y=max(0,min(Float(layout.rows)-0.00001,(rest.y-layout.rect[1])/layout.rect[3]*Float(layout.rows)))
        let ix=Int(x),iy=Int(y),u=x-Float(ix),v=y-Float(iy)
        let a=iy*(layout.columns+1)+ix,b=a+1,c=a+layout.columns+1,d=c+1
        func p(_ i: Int) -> SIMD2<Float> { SIMD2(mesh.positions[2*i],mesh.positions[2*i+1]) }
        return u+v<=1 ? p(a)*(1-u-v)+p(b)*u+p(c)*v : p(b)*(1-v)+p(d)*(u+v-1)+p(c)*(1-u)
    }
}
