import Foundation

/// Standard exp3 values use the same Add/Multiply/Overwrite rules on both hosts.
public struct CubismExpression: Codable, Sendable {
    public struct Parameter: Codable, Sendable {
        public let Id: String
        public let Value: Float
        public let Blend: String
    }
    public let `Type`: String
    public let FadeInTime: Double
    public let FadeOutTime: Double
    public let Parameters: [Parameter]
    public func apply(to base: [String:Float],weight: Float = 1) -> [String:Float] {
        var result = base
        for p in Parameters {
            let old = result[p.Id] ?? 0
            switch p.Blend {
            case "Multiply": result[p.Id] = old*(1+(p.Value-1)*weight)
            case "Overwrite": result[p.Id] = old+(p.Value-old)*weight
            default: result[p.Id] = old+p.Value*weight
            }
        }
        return result
    }
    public static let presets: [String:CubismExpression] = {
        func expression(_ values: [(String,Float,String)]) -> CubismExpression {
            CubismExpression(Type:"Live2D Expression",FadeInTime:0.45,FadeOutTime:0.45,
                             Parameters:values.map { Parameter(Id:$0.0,Value:$0.1,Blend:$0.2) })
        }
        var result: [String:CubismExpression] = [:]
        for style in ExpressionStyle.allCases {
            var values=style.face.sorted { $0.key<$1.key }.map { ($0.key,$0.value,$0.key.hasSuffix("Open") ? "Multiply":"Add") }
            if style.restingMouth>0 { values.append(("ParamMouthOpenY",style.restingMouth,"Add")) }
            result[style.rawValue] = expression(values)
        }
        result["neutral"] = expression([])
        result["happy"] = result["warm"];result["thinking"] = result["curious"]
        return result
    }()
}

public struct ExpressionPlayback {
    public let expressions: [String:CubismExpression]
    private var weights: [String:Float] = [:]
    private var time: Double?
    public init(directory: URL) throws {
        var result: [String:CubismExpression] = [:]
        for mood in Mood.allCases {
            result[mood.rawValue] = try JSONDecoder().decode(CubismExpression.self,from:Data(contentsOf:directory.appendingPathComponent("expressions/\(mood.rawValue).exp3.json")))
        }
        expressions = result
    }
    public mutating func apply(_ base: [String:Float],mood: Mood,time now: Double) -> [String:Float] {
        let dt = max(0,min(0.1,now-(time ?? now)))
        if time == nil || now <= time! { weights = [mood.rawValue:1] }
        time = now
        for name in expressions.keys {
            let target: Float = name == mood.rawValue ? 1:0
            let old = weights[name] ?? 0,step = Float(dt/max(0.01,expressions[name]!.FadeInTime))
            weights[name] = min(old+step,max(old-step,target))
        }
        var result = base
        for name in expressions.keys.sorted() { result = expressions[name]!.apply(to:result,weight:weights[name] ?? 0) }
        return result
    }
}
