import Foundation

/// Clef supplies meaning, never raw mesh/parameter commands. Inspired by
/// Soullink's semantic layer and channel ownership; independently authored for Mio.
public enum ExpressionStyle: String, Codable, CaseIterable, Sendable {
    case neutral, warm, joyful, curious, concerned, surprised, determined, sleepy
    public var title: String {
        switch self {
        case .neutral: return "平静"
        case .warm: return "温柔"
        case .joyful: return "喜悦"
        case .curious: return "好奇"
        case .concerned: return "关心"
        case .surprised: return "惊讶"
        case .determined: return "坚定"
        case .sleepy: return "困倦"
        }
    }
    public var description: String {
        switch self {
        case .neutral: return "平静倾听：眉眼放松，嘴角自然"
        case .warm: return "温柔回应：眉尾舒展，轻微笑眼，柔和微笑"
        case .joyful: return "分享喜悦：眉毛扬起，眼睛带笑，嘴角明显上扬"
        case .curious: return "好奇思考：一侧眉毛略抬，目光专注，轻抿嘴"
        case .concerned: return "关心安慰：内眉轻抬，目光柔和，嘴角收敛"
        case .surprised: return "短暂惊讶：眉毛抬起，眼睛张开，圆口形"
        case .determined: return "坚定鼓励：内眉略收，目光专注，嘴角自信"
        case .sleepy: return "困倦晚安：眉毛放松，眼睑低垂，嘴部放松"
        }
    }
    public var mood: Mood {
        switch self {
        case .neutral: return .neutral
        case .warm,.joyful,.determined: return .happy
        case .curious,.surprised: return .thinking
        case .concerned: return .concerned
        case .sleepy: return .sleepy
        }
    }
    public static func from(_ mood: Mood) -> Self {
        switch mood { case .neutral: return .neutral;case .happy: return .warm;case .thinking: return .curious;case .concerned: return .concerned;case .sleepy: return .sleepy }
    }
    /// Valence, arousal, dominance targets; interpolated as well as facial channels.
    public var vad: [Float] {
        switch self {
        case .neutral: return [0,0,0]
        case .warm: return [0.55,-0.25,0.1]
        case .joyful: return [0.85,0.65,0.35]
        case .curious: return [0.1,0.3,-0.1]
        case .concerned: return [-0.35,-0.15,-0.2]
        case .surprised: return [0.05,0.85,-0.3]
        case .determined: return [0.45,0.35,0.7]
        case .sleepy: return [0,-0.8,-0.25]
        }
    }
    public var restingMouth: Float { self == .surprised ? 0.55:0 }
    public var face: [String:Float] {
        // Height, inner-brow angle, eyelid aperture, smile/frown, lip rounding.
        let a: [Float]
        switch self {
        case .neutral: a=[0,0,0,0,1,1,0,0]
        case .warm: a=[0.12,0.12,0.08,0.08,0.96,0.96,0.5,0]
        case .joyful: a=[0.45,0.45,-0.2,-0.2,0.83,0.83,0.95,0]
        case .curious: a=[0.6,-0.15,0.3,-0.1,1,0.95,-0.22,0.12]
        case .concerned: a=[0.25,0.25,0.75,0.75,0.9,0.9,-0.85,0.1]
        case .surprised: a=[0.85,0.85,0,0,1.1,1.1,-0.25,0.9]
        case .determined: a=[-0.18,-0.18,-0.6,-0.6,0.94,0.94,0.25,0.18]
        case .sleepy: a=[-0.2,-0.2,0.12,0.12,0.58,0.58,0,0.12]
        }
        var result=Dictionary(uniqueKeysWithValues:zip(EmotionPlayback.faceIDs,a))
        let smile: Float=self == .joyful ? 0.75:self == .warm ? 0.25:0
        result["ParamEyeLSmile"]=smile;result["ParamEyeRSmile"]=smile
        return result
    }
}
public enum ExpressionIntensity: String, Codable, CaseIterable, Sendable {
    case subtle, normal, strong
    public var amount: Float { switch self { case .subtle:return 0.45;case .normal:return 0.72;case .strong:return 1 } }
}
public enum ExpressionHand: String, Codable, CaseIterable, Sendable {
    case rest, wave, explain, chin, encourage
    public var description: String {
        switch self {
        case .rest:return "自然放下双手，倾听、安慰、晚安或安静陪伴"
        case .wave:return "掌心向外招手，仅欢迎或告别，不用于每句回应"
        case .explain:return "单手舒展手指、摊掌，解释、分享或邀请继续说"
        case .chin:return "食指轻抵下巴，其余手指收拢，思考问题"
        case .encourage:return "单手轻握拳，表示加油和鼓励，不挥拳"
        }
    }
}
public struct EmotionalExpression: Codable, Sendable, Equatable {
    public let style: ExpressionStyle
    public let intensity: ExpressionIntensity
    public let hand: ExpressionHand
    public init(style: ExpressionStyle,intensity: ExpressionIntensity = .normal,hand: ExpressionHand = .rest) {
        self.style=style;self.intensity=intensity;self.hand=hand
    }
}

/// A bounded continuous layer. Speech owns aperture, emotion owns mouth form;
/// blink multiplies lid aperture so a mood can never cancel an actual blink.
public struct EmotionPlayback {
    public static let faceIDs = ["ParamBrowLY","ParamBrowRY","ParamBrowLAngle","ParamBrowRAngle","ParamEyeLOpen","ParamEyeROpen","ParamMouthForm","ParamMouthRound","ParamEyeLSmile","ParamEyeRSmile"]
    private var current = ExpressionStyle.neutral.face
    public private(set) var vad: [Float] = [0,0,0]
    private var last: Double?
    private var restingMouth: Float = 0
    public init() {}
    public mutating func apply(_ base: [String:Float],expression: EmotionalExpression,time: Double,mouthOwned: Bool = true) -> [String:Float] {
        let neutral=ExpressionStyle.neutral.face,target=expression.style.face,gain=expression.intensity.amount
        let reset=last == nil || time < last!
        let dt=max(0,min(0.1,time-(last ?? time))),blend=reset ? 1:Float(1-exp(-dt/0.22))
        last=time
        for id in Self.faceIDs {
            let desired=neutral[id]!+(target[id]!-neutral[id]!)*gain
            current[id]! += (desired-current[id]!)*blend
        }
        for i in 0..<3 { vad[i] += (expression.style.vad[i]*gain-vad[i])*blend }
        restingMouth += (expression.style.restingMouth*gain-restingMouth)*blend
        var result=base
        if !mouthOwned { result["ParamMouthOpenY"] = restingMouth }
        for id in Self.faceIDs {
            if id.hasSuffix("Open") { result[id]=(base[id] ?? 1)*current[id]! }
            else { result[id]=current[id]! }
        }
        return result
    }
    public static func profileData() throws -> Data {
        let styles = Dictionary(uniqueKeysWithValues:ExpressionStyle.allCases.map { ($0.rawValue,["face":$0.face,"vad":$0.vad,"restingMouth":$0.restingMouth] as [String:Any]) })
        return try JSONSerialization.data(withJSONObject:["version":1,"smoothingSeconds":0.22,
            "styles":styles,"intensities":Dictionary(uniqueKeysWithValues:ExpressionIntensity.allCases.map {($0.rawValue,$0.amount)}),
            "hands":ExpressionHand.allCases.map(\.rawValue),"mouthApertureOwner":"speech","classifier":"clef-omni /v1/systemone"],options:[.prettyPrinted,.sortedKeys])
    }
}
