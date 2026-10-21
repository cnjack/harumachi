import Foundation
import AppKit
import ImageIO
import MioCore

// Build authored keyforms, not a replacement runtime format. The adjacent Java
// bridge imports these into Cubism's model source and official MOC3 exporter.
struct SourceRig: Decodable {
    struct Layer: Codable {
        var id: String; var texture: String; var rect: [Float]; var group: String
        var joints: [[Float]]?; var defaultVisible: Bool?; var bendSpans: [Float]?; var jointPiece: String?
    }
    var canvas: [Int]; var origin: [Float]; var layers: [Layer]; var layoutRevision: String
}
struct Parameter: Codable {
    var id: String; var min: Float; var max: Float; var value: Float
}
let root = URL(fileURLWithPath:CommandLine.arguments[1])
let out = URL(fileURLWithPath:CommandLine.arguments[2])
try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
let resources = root.appendingPathComponent("native/mio-companion/Sources/MioApp/Resources/Mio")
let source = try JSONDecoder().decode(SourceRig.self,from:Data(contentsOf:resources.appendingPathComponent("Mio.rig.json")))
var layers: [SourceRig.Layer] = []
for layer in source.layers {
    if layer.group.hasPrefix("eyes_") {
        for side in ["right","left"] {
            var copy = layer;copy.id += "_"+side;copy.group += "_"+side;layers.append(copy)
        }
    } else { layers.append(layer) }
}
let parameters: [Parameter] = [
    .init(id:"ParamAngleX",min:-30,max:30,value:0),.init(id:"ParamAngleY",min:-30,max:30,value:0),
    .init(id:"ParamAngleZ",min:-12,max:12,value:0),.init(id:"ParamBodyAngleZ",min:-3,max:3,value:0),
    .init(id:"ParamBreath",min:0,max:1,value:0.5),
    .init(id:"ParamEyeLOpen",min:0,max:1,value:1),.init(id:"ParamEyeROpen",min:0,max:1,value:1),
    .init(id:"ParamMouthOpenY",min:0,max:1,value:0),
    .init(id:"ParamHairFront",min:-1,max:1,value:0),.init(id:"ParamHairBack",min:-1,max:1,value:0),
    .init(id:"ParamShoulderL",min:-2.2,max:2.2,value:-0.38),.init(id:"ParamShoulderR",min:-2.2,max:2.2,value:0.38),
    .init(id:"ParamElbowL",min:0,max:1.6,value:0.04),.init(id:"ParamElbowR",min:-2.2,max:3.1,value:-0.04),
    .init(id:"ParamWristL",min:-0.2,max:0.2,value:0),.init(id:"ParamWristR",min:-0.2,max:0.2,value:0),
    .init(id:"ParamHandL",min:0,max:4,value:0),.init(id:"ParamHandR",min:0,max:5,value:0),
    .init(id:"ParamHandOpenL",min:0,max:1,value:1),.init(id:"ParamHandOpenR",min:0,max:1,value:1),
    .init(id:"ParamHandCloseL",min:0,max:1,value:0),.init(id:"ParamHandCloseR",min:0,max:1,value:0),
    .init(id:"ParamThought",min:0,max:1,value:0),.init(id:"ParamTorsoLift",min:0,max:5,value:0)
]
let defaults = Dictionary(uniqueKeysWithValues:parameters.map { ($0.id,$0.value) })
let degree = Float.pi/180
func poseMotion(_ values: [String:Float]) -> PuppetMotion {
    var m = PuppetMotion(pose:RigPose(time:0,gesture:.idle))
    m.torso = 0;m.torsoLift = 0;m.head = 0;m.headShift = .zero
    m.leftShoulder = 0;m.rightShoulder = 0;m.leftElbow = values["ParamElbowL"] ?? 0.04
    m.rightElbow = values["ParamElbowR"] ?? -0.04
    m.leftWrist = values["ParamWristL"] ?? 0;m.rightWrist = values["ParamWristR"] ?? 0
    return m
}
func combinations(_ keys: [[Float]]) -> [[Float]] {
    if keys.isEmpty { return [[]] }
    var result: [[Float]] = [[]]
    for values in keys {
        result = values.flatMap { value in result.map { $0+[value] } }
    }
    return result
}
var binary = Data()
func appendFloats(_ floats: [Float]) -> Int {
    let offset = binary.count
    for value in floats {
        var bits = value.bitPattern.littleEndian
        withUnsafeBytes(of:&bits) { binary.append(contentsOf:$0) }
    }
    return offset
}
var descriptions: [[String:Any]] = []
let headGroups = ["head","hair","eyes_open","eyes_closed","mouth_open","mouth_closed"]
for (order,layer) in layers.enumerated() {
    let arm = layer.group.hasPrefix("arm_") || layer.group.hasPrefix("hand_")
    let hand = layer.group.hasPrefix("hand_")
    let head = headGroups.contains(layer.group) || layer.group.hasPrefix("eyes_")
    let left = layer.group.hasSuffix("_left")
    let side = left ? "L" : "R"
    var bindings: [(String,[Float])] = []
    var parent = "Body"
    var pivot = SIMD2<Float>(375,432)
    if arm {
        let upper = layer.jointPiece == "upper"
        parent = (hand ? "Wrist" : (upper ? "Shoulder" : "Elbow"))+side
        if hand { pivot = SIMD2(left ? 189:561,508) }
        else if upper { pivot = SIMD2(left ? 306:444,320) }
        else { pivot = SIMD2(left ? 248:502,418) }
        if hand { bindings = [("ParamHandOpen"+side,[0,0.5,1]),("ParamHandClose"+side,[0,1])] }
        else if upper {
            // Root-only tuck is authored in the MOC, under the same rotation
            // deformer as the rigid shaft. External players get identical art.
            bindings = [("ParamShoulder"+side,(-22...22).map { Float($0)/10 })]
        }
    } else if head {
        parent = "Head";pivot = SIMD2(375,305)
        bindings = []
        if layer.group == "hair" { bindings.append((layer.id == "hair_back" ? "ParamHairBack" : "ParamHairFront",[-1,0,1])) }
    } else if layer.group == "lower_body" {
        parent = "";pivot = .zero
        bindings = [("ParamBodyAngleZ",[-3,-2,-1,0,1,2,3]),("ParamTorsoLift",[0,5])]
    } else if layer.group == "thought_cloud" {
        bindings = [("ParamAngleX",[-30,0,30]),("ParamAngleY",[-30,0,30]),("ParamAngleZ",[-12,0,12])]
    } else if layer.group == "torso" {
        bindings = [("ParamAngleZ",[-12,-6,0,6,12]),("ParamAngleX",[-30,0,30]),("ParamAngleY",[-30,0,30]),("ParamBreath",[0,0.5,1]),("ParamTorsoLift",[0,5])]
    }
    let columns = hand ? 12 : (arm ? 24 : (head ? 8 : 20))
    let rows = hand ? 32 : (head ? 24 : 64)
    var base: [Float] = [];var indices: [Int] = []
    for y in 0...rows { for x in 0...columns {
        base += [layer.rect[0]+75+layer.rect[2]*Float(x)/Float(columns),layer.rect[1]+layer.rect[3]*Float(y)/Float(rows)]
    } }
    for y in 0..<rows { for x in 0..<columns {
        let a = y*(columns+1)+x,b = a+1,c = a+columns+1,d = c+1
        indices += [a,b,c,b,d,c]
    } }
    var forms: [[String:Any]] = []
    for keyValues in combinations(bindings.map(\.1)) {
        var values = defaults
        for ((id,_),value) in zip(bindings,keyValues) { values[id] = value }
        var motion = poseMotion(values)
        if arm { motion.leftElbow=0;motion.rightElbow=0;motion.leftWrist=0;motion.rightWrist=0 }
        var positions: [Float] = []
        for i in stride(from:0,to:base.count,by:2) {
            var p = SIMD2(base[i]-75,base[i+1])
            if arm,let joints = layer.joints {
                let shoulder = SIMD2(joints[0][0],joints[0][1]),elbow = SIMD2(joints[1][0],joints[1][1]),wrist = SIMD2(joints[2][0],joints[2][1])
                if hand {
                    let axis = wrist-elbow,direction = axis/sqrt(axis.x*axis.x+axis.y*axis.y),normal = SIMD2(-direction.y,direction.x)
                    let delta = p-wrist,along = delta.x*direction.x+delta.y*direction.y,across = delta.x*normal.x+delta.y*normal.y
                    let variant = layer.id == "hand_right_chin_front" ? "chin" : String(layer.id.split(separator:"_").last!)
                    let variantIndex = HandPresentation.variants.firstIndex(of:variant) ?? 0
                    let reaches: [Float] = [73,68,68,62,38,95],widths: [Float] = [20,34,34,20,20,40]
                    let open = values["ParamHandOpen"+side] ?? 1
                    let targetReach: Float = 62-24*(values["ParamHandClose"+side] ?? 0)
                    let closedLength = (targetReach-24)/(reaches[variantIndex]-24)
                    let length = closedLength+(1-closedLength)*open
                    let width = 20/widths[variantIndex]+(1-20/widths[variantIndex])*open
                    let q = max(0,min(1,(along-16)/16)),integral = 16*(q*q*q-0.5*q*q*q*q)+max(0,along-32)
                    p = wrist+direction*(along-(1-length)*integral)+normal*(across*(1+(width-1)*PuppetMotion.smooth(16,32,along)))
                }
                p = motion.armPoint(p,shoulder:shoulder,elbow:elbow,wrist:wrist,left:left,elbowBendSpan:layer.bendSpans?[0] ?? 104,wristBendSpan:layer.bendSpans?[1] ?? 30,upperArm:layer.jointPiece.map { $0 == "upper" },hand:hand)
                if layer.jointPiece == "upper" {
                    let angle = values["ParamShoulder"+side] ?? 0
                    p = PuppetMotion.sleeveRoot(p,shoulder:shoulder,elbow:elbow,lift:left ? angle:-angle)
                }
            } else if head {
                if layer.group == "hair" {
                    let sway = values[layer.id == "hair_back" ? "ParamHairBack" : "ParamHairFront"] ?? 0
                    p.x += sway*2.6*max(0,(p.y-95)/200)
                }
                // Head translation is authored on its parent rotation deformer.
            } else if layer.group == "lower_body" {
                var lower = motion;lower.torso = (values["ParamBodyAngleZ"] ?? 0)*degree;lower.torsoLift = values["ParamTorsoLift"] ?? 0
                p = lower.lowerBodyPoint(p)
            } else if layer.group == "thought_cloud" {
                p += SIMD2((values["ParamAngleX"] ?? 0)*0.1+(values["ParamAngleZ"] ?? 0)*degree*30,-(values["ParamAngleY"] ?? 0)*0.25)
            } else if layer.group == "torso" {
                let breath = ((values["ParamBreath"] ?? 0.5)-0.5)*2
                let upper = max(0,min(1,(750-p.y)/500))
                p.y -= breath*1.5*upper;p.x = 300+(p.x-300)*(1+breath*0.002*upper)
                var neck = motion;neck.head = (values["ParamAngleZ"] ?? 0)*degree
                neck.headShift = SIMD2((values["ParamAngleX"] ?? 0)*0.1,-(values["ParamAngleY"] ?? 0)*0.25)
                p = neck.neckPoint(p)
                p.y += (values["ParamTorsoLift"] ?? 0)*PuppetMotion.smooth(310,650,p.y)
            }
            positions += [p.x+75-pivot.x,p.y-pivot.y]
        }
        forms.append(["values":keyValues,"offset":appendFloats(positions)])
    }
    var opacity: [String:Any] = [:]
    if hand {
        let variant = layer.id == "hand_right_chin_front" ? "chin" : String(layer.id.split(separator:"_").last!)
        let index = HandPresentation.variants.firstIndex(of:variant) ?? 0
        opacity = ["parameter":"ParamHand"+side,"keys":Array(0...(left ? 4 : 5)),"values":Array(0...(left ? 4 : 5)).map { $0 == index ? 1 : 0 }]
        if layer.id == "hand_right_chin" { opacity = ["constant":0] }
    } else if layer.group.hasPrefix("eyes_") {
        opacity = ["parameter":layer.group.hasSuffix("_left") ? "ParamEyeLOpen" : "ParamEyeROpen","keys":[0,1],"values":layer.group.hasPrefix("eyes_open") ? [0,1] : [1,0]]
    } else if layer.group.hasPrefix("mouth_") {
        opacity = ["parameter":"ParamMouthOpenY","keys":[0,1],"values":layer.group == "mouth_open" ? [0,1] : [1,0]]
    } else if layer.group == "thought_cloud" {
        opacity = ["parameter":"ParamThought","keys":[0,1],"values":[0,1]]
    }
    descriptions.append(["id":layer.id,"parent":parent,"base":base,"indices":indices,"bindings":bindings.map { ["id":$0.0,"keys":$0.1] },"forms":forms,"opacity":opacity,"drawOrder":order*10,"rect":layer.rect.map { $0 },"columns":columns,"rows":rows])
}
let anchors = descriptions.map { spec -> [String:Any] in
    ["id":spec["id"]!,"rect":spec["rect"]!,"columns":spec["columns"]!,"rows":spec["rows"]!]
}
try JSONSerialization.data(withJSONObject:["meshes":anchors],options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("Mio.bindings.json"))
try binary.write(to:out.appendingPathComponent("forms.bin"))
let encodedParameters = try JSONSerialization.jsonObject(with:JSONEncoder().encode(parameters))
try JSONSerialization.data(withJSONObject:["parameters":encodedParameters,"meshes":descriptions,"sourceLayout":source.layoutRevision],options:[.sortedKeys]).write(to:out.appendingPathComponent("bake.json"))

// Produce a conventional RGB/8 PSD with the resolution resource required by
// Cubism's importer and independent left/right eyelid source layers.
extension Data {
    mutating func u16(_ n: Int) { append(UInt8((n>>8)&255));append(UInt8(n&255)) }
    mutating func u32(_ n: Int) { u16((n>>16)&65535);u16(n&65535) }
    mutating func ascii(_ s: String) { append(contentsOf:s.utf8) }
}
let width = 750,height = 1000,pixelCount = width*height
let rasters: [(SourceRig.Layer,[UInt8])] = layers.reversed().map { layer in
    let image = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(resources.appendingPathComponent(layer.texture) as CFURL,nil)!,0,nil)!
    var pixels = [UInt8](repeating:0,count:pixelCount*4)
    pixels.withUnsafeMutableBytes { ptr in
        let context = CGContext(data:ptr.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        if layer.group.hasPrefix("eyes_") {
            context.clip(to:CGRect(x:layer.group.hasSuffix("_left") ? 375 : 0,y:0,width:375,height:height))
        }
        let r = layer.rect
        context.draw(image,in:CGRect(x:CGFloat(r[0]+75),y:CGFloat(Float(height)-r[1]-r[3]),width:CGFloat(r[2]),height:CGFloat(r[3])))
    }
    return (layer,pixels)
}
func plane(_ pixels: [UInt8],_ channel: Int) -> Data {
    var result = Data(capacity:pixelCount)
    for i in 0..<pixelCount {
        let alpha = Int(pixels[i*4+3]),value = Int(pixels[i*4+channel])
        result.append(UInt8(channel != 3 && alpha>0 ? min(255,value*255/alpha) : value))
    }
    return result
}
var info = Data();info.u16(rasters.count)
for (layer,_) in rasters {
    info.u32(0);info.u32(0);info.u32(height);info.u32(width);info.u16(4)
    for channel in [0,1,2,-1] { info.u16(channel&65535);info.u32(2+pixelCount) }
    info.ascii("8BIMnorm");info.append(contentsOf:[255,0,layer.defaultVisible == false || layer.group.hasPrefix("eyes_closed") || layer.group == "mouth_open" ? 2 : 0,0])
    var extra = Data();extra.u32(0);extra.u32(0)
    let name = Array(layer.id.utf8);extra.append(UInt8(name.count));extra.append(contentsOf:name)
    while extra.count%4 != 0 { extra.append(0) }
    info.u32(extra.count);info.append(extra)
}
for (_,pixels) in rasters { for channel in 0..<4 { info.u16(0);info.append(plane(pixels,channel)) } }
if info.count%2 != 0 { info.append(0) }
var mask = Data();mask.u32(info.count);mask.append(info);mask.u32(0)
var resolution = Data();resolution.ascii("8BIM");resolution.u16(1005);resolution.u16(0);resolution.u32(16)
for _ in 0..<2 { resolution.u32(72<<16);resolution.u16(1);resolution.u16(1) }
var psd = Data();psd.ascii("8BPS");psd.u16(1);psd.append(contentsOf:[UInt8](repeating:0,count:6));psd.u16(4);psd.u32(height);psd.u32(width);psd.u16(8);psd.u16(3)
psd.u32(0);psd.u32(resolution.count);psd.append(resolution);psd.u32(mask.count);psd.append(mask)
var composite = [UInt8](repeating:0,count:pixelCount*4)
for (layer,pixels) in rasters.reversed() {
    let visible = layer.defaultVisible != false && !layer.group.hasPrefix("eyes_closed") && layer.group != "mouth_open"
    if !visible { continue }
    for i in 0..<pixelCount { let alpha = Int(pixels[i*4+3]);for c in 0..<4 { composite[i*4+c] = UInt8(min(255,Int(pixels[i*4+c])+Int(composite[i*4+c])*(255-alpha)/255)) } }
}
psd.u16(0);for channel in 0..<4 { psd.append(plane(composite,channel)) }
try psd.write(to:out.appendingPathComponent("Mio.psd"))
print("Cubism input: \(layers.count) source layers, \(descriptions.reduce(0) { $0+($1["forms"] as! [[String:Any]]).count }) keyforms, \(binary.count) position bytes")

let motions = out.appendingPathComponent("motions")
try FileManager.default.createDirectory(at:motions,withIntermediateDirectories:true)
for gesture in [CharacterGesture.idle,.wave,.stretch,.think,.talk] {
    let frames = Int(gesture.duration*30)
    let samples = (0...frames).map { frame -> [String:Float] in
        let t = Double(frame)/30
        let pose = RigPose(time:t,speaking:gesture == .talk,gesture:gesture,gestureTime:t)
        return CubismParameters.values(pose:pose,motion:PuppetMotion(pose:pose))
    }
    var segmentsCount = 0,pointsCount = 0
    let curves: [[String:Any]] = parameters.map { parameter in
        let stepped = ["ParamHandL","ParamHandR","ParamEyeLOpen","ParamEyeROpen","ParamMouthOpenY"].contains(parameter.id)
        var segments: [Double] = [0,Double(samples[0][parameter.id]!)]
        for frame in 1...frames { segments += [stepped ? 2 : 0,Double(frame)/30,Double(samples[frame][parameter.id]!)] }
        segmentsCount += frames;pointsCount += frames+1
        return ["Target":"Parameter","Id":parameter.id,"Segments":segments]
    }
    let motion: [String:Any] = ["Version":3,"Meta":["Duration":gesture.duration,"Fps":30,"Loop":false,"AreBeziersRestricted":true,"CurveCount":curves.count,"TotalSegmentCount":segmentsCount,"TotalPointCount":pointsCount,"UserDataCount":0,"TotalUserDataSize":0,"FadeInTime":0,"FadeOutTime":0],"Curves":curves,"UserData":[]]
    try JSONSerialization.data(withJSONObject:motion,options:[.sortedKeys]).write(to:motions.appendingPathComponent(gesture.rawValue+".motion3.json"))
}
