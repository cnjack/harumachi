// Deterministic atlas slicing only; artwork comes from imagegen, never colour-keyed.
import AppKit
import ImageIO

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let input = root.appendingPathComponent("art/live2d/mio/parts-atlas.png")
let out = root.appendingPathComponent("native/mio-companion/Sources/MioApp/Resources/Mio")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let source = CGImageSourceCreateWithURL(input as CFURL, nil)!
let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil)!
let bodyAtlas = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(
    root.appendingPathComponent("art/live2d/mio/articulated/body-arms-atlas.png") as CFURL, nil)!, 0, nil)!
let crops: [(String, CGRect, [Double], String)] = [
    ("body", CGRect(x: 100, y: 0, width: 500, height: 1024), [155, 252, 290, 730], "body"),
    ("arm_left", CGRect(x: 640, y: 140, width: 370, height: 540), [65, 285, 194, 280], "arm_left"),
    ("arm_right", CGRect(x: 1160, y: 140, width: 376, height: 540), [341, 285, 194, 280], "arm_right"),
    ("hair_back", CGRect(x: 444, y: 55, width: 445, height: 530), [176, 36, 248, 260], "hair"),
    ("face", CGRect(x: 945, y: 155, width: 350, height: 322), [214, 92, 172, 180], "head"),
    ("hair_front", CGRect(x: 1320, y: 60, width: 454, height: 535), [176, 36, 248, 260], "hair"),
    ("eyes_open", CGRect(x: 20, y: 630, width: 419, height: 216), [242, 158, 116, 44.64], "eyes_open"),
    ("eyes_closed", CGRect(x: 475, y: 632, width: 400, height: 190), [242, 158, 116, 39.42], "eyes_closed"),
    ("mouth_closed", CGRect(x: 1010, y: 715, width: 220, height: 110), [282, 229.2, 36, 9.6], "mouth_closed"),
    ("mouth_open", CGRect(x: 1460, y: 685, width: 180, height: 145), [289, 227.7, 22, 12.6], "mouth_open")
]
// Scale every head part together around the neck in the source layout. Baking
// this here keeps the PSD and renderer identical and preserves facial ratios.
// The selected overlay preview is 20% smaller than the previous 0.92 layout.
let headScale = 0.92 * 0.80
let neckAnchor = CGPoint(x: 300, y: 268)
func fittedRect(_ rect: [Double], group: String) -> [Double] {
    guard group != "body", !group.hasPrefix("arm_") else { return rect }
    return [neckAnchor.x + (rect[0] - neckAnchor.x) * headScale,
            neckAnchor.y + (rect[1] - neckAnchor.y) * headScale,
            rect[2] * headScale, rect[3] * headScale]
}
var layers: [[String: Any]] = []
for (name, crop, originalRect, group) in crops {
    let rect = fittedRect(originalRect, group: group)
    let sourceAtlas = group == "body" || group.hasPrefix("arm_") ? bodyAtlas : atlas
    let part = sourceAtlas.cropping(to: crop)!
    let width = part.width, height = part.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let cs = CGColorSpaceCreateDeviceRGB()
    bytes.withUnsafeMutableBytes { ptr in
        let ctx = CGContext(data: ptr.baseAddress, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(part, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    var x0 = width, y0 = height, x1 = 0, y1 = 0
    for y in 0..<height { for x in 0..<width {
        let i = (y * width + x) * 4
        // Quantization dust in the generated alpha is not part of the sprite.
        if bytes[i + 3] < 12 { bytes[i] = 0; bytes[i + 1] = 0; bytes[i + 2] = 0; bytes[i + 3] = 0 }
        if bytes[i + 3] > 32 { x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) }
    } }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                        bytesPerRow: width * 4, space: cs, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                        provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    // CGImage cropping uses top-left image coordinates; byte rows already preserve source orientation.
    let trimmed = image.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1))!
    let path = out.appendingPathComponent(name + ".png")
    let destination = CGImageDestinationCreateWithURL(path as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, trimmed, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("PNG write failed") }
    var layer: [String: Any] = ["id": name, "texture": name + ".png", "rect": rect, "group": group,
                               "sourceCrop": [crop.minX, crop.minY, crop.width, crop.height],
                               "sourceAtlas": group == "body" || group.hasPrefix("arm_") ? "articulated/body-arms-atlas.png" : "parts-atlas.png"]
    // Pivots measured on the trimmed sleeve cap, elbow fold and wrist crease.
    // Arc spans cover the full sleeve width, rather than a narrow skinning seam.
    if group == "arm_left" { layer["joints"] = [[231, 320], [173, 418], [114, 508]] }
    if group == "arm_right" { layer["joints"] = [[369, 320], [427, 418], [486, 508]] }
    if group.hasPrefix("arm_") {
        layer["bendSpans"] = [104, 30]
        layer["binding"] = "rigid-shoulder-arc-elbow-wrist"
    }
    layers.append(layer)
    print("\(name): \(trimmed.width)x\(trimmed.height)")
}
// Additional painted source parts. All processing below is registration,
// geometric cutting and alpha-preserving atlas assembly, not generated paint.
func load(_ relative: String) -> CGImage {
    CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(root.appendingPathComponent(relative) as CFURL, nil)!, 0, nil)!
}
func write(_ image: CGImage, _ name: String) {
    var bytes = rgba(image)
    for i in stride(from: 0, to: bytes.count, by: 4) where bytes[i+3] < 12 {
        bytes[i] = 0; bytes[i+1] = 0; bytes[i+2] = 0; bytes[i+3] = 0
    }
    let clean = makeImage(bytes, width:image.width, height:image.height)
    let destination = CGImageDestinationCreateWithURL(out.appendingPathComponent(name + ".png") as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, clean, nil)
    precondition(CGImageDestinationFinalize(destination))
}
func rgba(_ image: CGImage) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    bytes.withUnsafeMutableBytes { p in
        let context = CGContext(data: p.baseAddress, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return bytes
}
func makeImage(_ bytes: [UInt8], width: Int, height: Int) -> CGImage {
    CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
}
let torsoAtlas = load("art/live2d/mio/pose-parts/torso-overlaps.png")
for (id, crop, rect, group) in [
    ("torso", CGRect(x: 55, y: 20, width: 480, height: 670), [195.0,252,210,290], "torso"),
    ("lower_body", CGRect(x: 550, y: 25, width: 520, height: 980), [155.0,398,290,584], "lower_body"),
    ("shoulder_left", CGRect(x: 1130, y: 150, width: 150, height: 280), [220.0,307,30,51], "shoulder_left"),
    ("shoulder_right", CGRect(x: 1320, y: 150, width: 150, height: 280), [350.0,307,30,51], "shoulder_right")
] {
    let image = torsoAtlas.cropping(to: crop)!
    // Trim actual alpha bounds so the target rectangles refer to visible art.
    let bytes = rgba(image)
    var x0 = image.width, y0 = image.height, x1 = 0, y1 = 0
    for y in 0..<image.height { for x in 0..<image.width where bytes[(y * image.width + x) * 4 + 3] > 32 {
        x0 = min(x0,x); x1 = max(x1,x); y0 = min(y0,y); y1 = max(y1,y)
    } }
    write(image.cropping(to: CGRect(x: x0,y: y0,width: x1-x0+1,height: y1-y0+1))!, id)
    layers.append(["id":id,"texture":id+".png","rect":rect,"group":group,
        "sourceAtlas":"pose-parts/torso-overlaps.png","sourceCrop":[crop.minX,crop.minY,crop.width,crop.height]])
}
layers.removeAll { $0["id"] as? String == "body" }
// The existing hands remain the relaxed variant; new orientations share the
// same wrist and rest-space texture rectangle for interpolation in the shader.
for side in ["left", "right"] {
    let armIndex = layers.firstIndex { $0["id"] as? String == "arm_\(side)" }!
    let arm = layers[armIndex]
    let r = arm["rect"] as! [Double]
    let joints = arm["joints"] as! [[Int]]
    let shoulder = CGPoint(x: joints[0][0], y: joints[0][1])
    let elbow = CGPoint(x: joints[1][0], y: joints[1][1])
    let wrist = CGPoint(x: joints[2][0], y: joints[2][1])
    let dx = wrist.x-elbow.x, dy = wrist.y-elbow.y, length = hypot(dx,dy)
    let d = CGPoint(x: dx/length,y: dy/length)
    let source = load("native/mio-companion/Sources/MioApp/Resources/Mio/arm_\(side).png")
    let original = rgba(source)
    func cut(_ name: String, _ keep: (Double, Double) -> Bool) {
        var bytes = original
        for y in 0..<source.height { for x in 0..<source.width {
            let px = r[0] + (Double(x)+0.5)/Double(source.width)*r[2]
            let py = r[1] + (Double(y)+0.5)/Double(source.height)*r[3]
            if !keep(px,py) {
                let i = (y*source.width+x)*4
                bytes[i] = 0; bytes[i+1] = 0; bytes[i+2] = 0; bytes[i+3] = 0
            }
        } }
        write(makeImage(bytes,width:source.width,height:source.height),name)
    }
    func along(_ x: Double, _ y: Double, _ origin: CGPoint) -> Double { (x-origin.x)*d.x+(y-origin.y)*d.y }
    // Upper arm root is behind the torso; the sleeve below it is in front.
    // Registered overlap and a 30px feather keep the draw-order split continuous.
    cut("arm_\(side)") { x,y in along(x,y,elbow) < -8 }
    cut("sleeve_\(side)") { x,y in along(x,y,shoulder) >= 20 && along(x,y,wrist) < -54 }
    let sleeveImage = load("native/mio-companion/Sources/MioApp/Resources/Mio/sleeve_\(side).png")
    var sleeveBytes = rgba(sleeveImage)
    for y in 0..<sleeveImage.height { for x in 0..<sleeveImage.width {
        let px = r[0]+(Double(x)+0.5)/Double(sleeveImage.width)*r[2]
        let py = r[1]+(Double(y)+0.5)/Double(sleeveImage.height)*r[3]
        let fraction = max(0,min(1,(along(px,py,shoulder)-20)/30))
        let opacity = fraction*fraction*(3-2*fraction)
        for c in 0..<4 {
            let i = (y*sleeveImage.width+x)*4+c
            sleeveBytes[i] = UInt8(Double(sleeveBytes[i])*opacity)
        }
    } }
    write(makeImage(sleeveBytes,width:sleeveImage.width,height:sleeveImage.height),"sleeve_\(side)")
    var sleeve = arm; sleeve["id"] = "sleeve_\(side)"; sleeve["texture"] = "sleeve_\(side).png"
    layers.append(sleeve)
    cut("hand_\(side)_relaxed") { x,y in along(x,y,wrist) >= -62 }
    let handRect = [r[0]-20,r[1]-20,r[2]+40,r[3]+50]
    let relaxed = load("native/mio-companion/Sources/MioApp/Resources/Mio/hand_\(side)_relaxed.png")
    let resolution: CGFloat = 3
    let width = Int(handRect[2]*resolution), height = Int(handRect[3]*resolution)
    func context() -> CGContext {
        let ctx = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x:resolution,y:resolution)
        return ctx
    }
    let relaxedContext = context()
    relaxedContext.draw(relaxed,in:CGRect(x:20,y:30,width:r[2],height:r[3]))
    write(relaxedContext.makeImage()!,"hand_\(side)_relaxed")
    // Rig side is screen side, not anatomical side. The generated hand sheets
    // put the character's left hand in the left column; read the opposite
    // column for each on-screen arm. Never mirror the shoulder or whole rig.
    let sourceLeft = side == "right"
    let variants: [(String,String,CGPoint)] = [
        ("palm","palms-out",CGPoint(x: sourceLeft ? 425 : 1110,y:500)),
        ("back","hands-back",CGPoint(x: sourceLeft ? 443 : 1092,y:500)),
        ("inward","hands-inward",CGPoint(x: sourceLeft ? 437 : 1092,y:465))
    ]
    for (variant, file, pivot) in variants {
        let atlas = load("art/live2d/mio/pose-parts/\(file).png")
        let cropX = sourceLeft ? 150 : 850
        let image = atlas.cropping(to:CGRect(x:cropX,y:40,width:600,height:930))!
        let context = context()
        context.translateBy(x:wrist.x-handRect[0],y:handRect[3]-(wrist.y-handRect[1]))
        context.rotate(by: atan2(d.x,d.y))
        let sx: CGFloat = 0.17, sy: CGFloat = 0.16
        context.draw(image,in:CGRect(x:(CGFloat(cropX)-pivot.x)*sx,
            y:(pivot.y-40-CGFloat(image.height))*sy,width:CGFloat(image.width)*sx,height:CGFloat(image.height)*sy))
        write(context.makeImage()!,"hand_\(side)_\(variant)")
    }
    for variant in ["relaxed","palm","back","inward"] {
        var hand = arm
        hand["id"] = "hand_\(side)_\(variant)"
        hand["texture"] = "hand_\(side)_\(variant).png"
        hand["group"] = "hand_\(side)"
        hand["rect"] = handRect
        hand["variant"] = variant
        hand["defaultVisible"] = variant == "relaxed"
        hand["sourceAtlas"] = variant == "relaxed" ? "articulated/body-arms-atlas.png" :
            "pose-parts/\(variant == "palm" ? "palms-out" : "hands-\(variant)").png"
        hand["wristRegistration"] = [wrist.x,wrist.y]
        hand["anatomicalHand"] = side == "left" ? "right" : "left"
        if variant != "relaxed" {
            hand["sourceColumn"] = sourceLeft ? "left" : "right"
            hand["sourceCrop"] = [sourceLeft ? 150 : 850,40,600,930]
        }
        layers.append(hand)
    }
}
let order = ["hair_back", "lower_body", "shoulder_left", "shoulder_right", "arm_left", "arm_right", "torso",
             "sleeve_left",
             "hand_left_relaxed", "hand_left_palm", "hand_left_back", "hand_left_inward",
             "hand_right_relaxed", "hand_right_palm", "hand_right_back", "hand_right_inward",
             "sleeve_right", "face", "eyes_open", "eyes_closed", "mouth_closed", "mouth_open", "hair_front"]
layers.sort { order.firstIndex(of: $0["id"] as! String)! < order.firstIndex(of: $1["id"] as! String)! }
let manifest: [String: Any] = ["format": "harumachi-layer-rig", "version": 1, "name": "澪", "canvas": [750, 1000],
                              "origin": [-75, 0],
                              "layoutRevision": "20261020-head20-v7",
                              "cubismCompatible": false, "layers": layers,
                              "parameters": ["ParamAngleX", "ParamAngleY", "ParamBodyAngleZ", "ParamBreath", "ParamEyeLOpen", "ParamEyeROpen", "ParamMouthOpenY"]]
let json = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
try json.write(to: out.appendingPathComponent("Mio.rig.json"))
try json.write(to: root.appendingPathComponent("art/live2d/mio/Mio.rig.json"))
