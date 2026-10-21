import Foundation

/// Reads the model's physics3 particle strands. No character-specific spring
/// constants live in the renderer. Fixed 120 Hz integration bounds frame jitter.
public struct CubismPhysics {
    private struct Point: Decodable { let X,Y: Float; var vector: SIMD2<Float> { SIMD2(X,Y) } }
    private struct Reference: Decodable { let Id: String }
    private struct Input: Decodable { let Source: Reference; let Weight: Float; let `Type`: String; let Reflect: Bool }
    private struct Output: Decodable { let Destination: Reference; let VertexIndex: Int; let Scale,Weight: Float; let `Type`: String; let Reflect: Bool }
    private struct Vertex: Decodable { let Position: Point; let Mobility,Delay,Acceleration,Radius: Float }
    private struct Range: Decodable { let Minimum,Default,Maximum: Float }
    private struct Normalization: Decodable { let Position,Angle: Range }
    private struct Setting: Decodable { let Input: [Input]; let Output: [Output]; let Vertices: [Vertex]; let Normalization: Normalization }
    private struct Forces: Decodable { let Gravity,Wind: Point }
    private struct Meta: Decodable { let EffectiveForces: Forces }
    private struct Document: Decodable { let Version: Int; let Meta: Meta; let PhysicsSettings: [Setting] }
    private struct Particle { var position,velocity: SIMD2<Float>; var gravity = SIMD2<Float>(0,1) }
    private let document: Document
    private let ranges: [String:CubismModel.Parameter]
    private var strands: [[Particle]]
    private var previousInput: [String:Float] = [:]
    private var clock: Double?
    private var remainder: Double = 0
    public init(data: Data,parameters: [CubismModel.Parameter]) throws {
        document = try JSONDecoder().decode(Document.self,from:data)
        ranges = Dictionary(uniqueKeysWithValues:parameters.map { ($0.id,$0) })
        guard document.Version == 3,document.PhysicsSettings.allSatisfy({ setting in
            setting.Vertices.count >= 2 && setting.Vertices.allSatisfy { $0.Radius >= 0 && $0.Delay > 0 && $0.Mobility >= 0 && $0.Mobility <= 1 } &&
            setting.Output.allSatisfy { $0.VertexIndex > 0 && $0.VertexIndex < setting.Vertices.count && ["X","Y","Angle"].contains($0.Type) }
        }) else { throw CubismModel.Failure(message:"Invalid physics3 strand") }
        strands = document.PhysicsSettings.map { $0.Vertices.map { Particle(position:$0.Position.vector,velocity:.zero) } }
    }
    private func normalized(_ value: Float,_ id: String,_ range: Range) -> Float {
        guard let source=ranges[id] else { return 0 }
        let middle=(source.minimum+source.maximum)/2
        let v=max(source.minimum,min(source.maximum,value))-middle
        return range.Default + (v >= 0 ? v/max(0.000001,source.maximum-middle)*(range.Maximum-range.Default) : v/max(0.000001,middle-source.minimum)*(range.Default-range.Minimum))
    }
    private func rotate(_ v: SIMD2<Float>,_ a: Float) -> SIMD2<Float> { SIMD2(v.x*cos(a)-v.y*sin(a),v.x*sin(a)+v.y*cos(a)) }
    private func unit(_ v: SIMD2<Float>) -> SIMD2<Float> { v/max(0.000001,sqrt(v.x*v.x+v.y*v.y)) }
    private func angle(_ a: SIMD2<Float>,_ b: SIMD2<Float>) -> Float { atan2(a.x*b.y-a.y*b.x,a.x*b.x+a.y*b.y) }
    private mutating func step(_ values: [String:Float],dt: Float) {
        for (i,setting) in document.PhysicsSettings.enumerated() {
            var translation=SIMD2<Float>.zero,rotation: Float=0
            for input in setting.Input {
                let range=input.Type == "Angle" ? setting.Normalization.Angle:setting.Normalization.Position
                let value=normalized(values[input.Source.Id] ?? 0,input.Source.Id,range)*input.Weight/100*(input.Reflect ? 1:-1)
                switch input.Type { case "X":translation.x += value;case "Y":translation.y += value;default:rotation += value }
            }
            let radians=rotation*Float.pi/180,gravity=SIMD2(sin(radians),cos(radians))
            strands[i][0].position=rotate(translation,-radians)
            for j in 1..<setting.Vertices.count {
                let spec=setting.Vertices[j],old=strands[i][j].position,parent=strands[i][j-1].position
                let delay=spec.Delay*dt*30
                let direction=rotate(old-parent,angle(strands[i][j].gravity,gravity)/5)
                var point=parent+direction+strands[i][j].velocity*delay+(gravity*spec.Acceleration+document.Meta.EffectiveForces.Wind.vector)*delay*delay
                point=parent+unit(point-parent)*spec.Radius
                if abs(point.x)<0.001*setting.Normalization.Position.Maximum { point.x=0 }
                strands[i][j].velocity=(point-old)/max(0.000001,delay)*spec.Mobility
                strands[i][j].position=point;strands[i][j].gravity=gravity
            }
        }
    }
    public mutating func update(_ values: [String:Float],time now: Double) -> [String:Float] {
        if let clock,now >= clock,now-clock < 0.5 {
            let dt=now-clock;remainder += dt
            var consumed=0.0
            while remainder >= 1.0/120 {
                consumed += 1.0/120
                let fraction=Float(min(1,consumed/max(0.000001,dt)))
                var input=values
                for (id,value) in values { input[id]=(previousInput[id] ?? value)*(1-fraction)+value*fraction }
                step(input,dt:1.0/120);remainder -= 1.0/120
            }
        } else {
            strands=document.PhysicsSettings.map { $0.Vertices.map { Particle(position:$0.Position.vector,velocity:.zero) } }
            remainder=0
            // Settle against the initial input rather than swing from an unrelated
            // zero pose on launch or after a suspended window resumes.
            for _ in 0..<240 { step(values,dt:1.0/120) }
        }
        clock=now;previousInput=values
        var result=values
        for (i,setting) in document.PhysicsSettings.enumerated() { for output in setting.Output {
            let j=output.VertexIndex,v=strands[i][j].position-strands[i][j-1].position
            var value: Float
            switch output.Type {
            case "X":value=v.x
            case "Y":value=v.y
            default:
                let parent=j>1 ? strands[i][j-1].position-strands[i][j-2].position : -document.Meta.EffectiveForces.Gravity.vector
                value=angle(parent,v)
            }
            value *= output.Scale*(output.Reflect ? -1:1)
            let id=output.Destination.Id
            if let range=ranges[id] { value=max(range.minimum,min(range.maximum,value)) }
            result[id]=(values[id] ?? 0)*(1-output.Weight/100)+value*output.Weight/100
        } }
        return result
    }
}
