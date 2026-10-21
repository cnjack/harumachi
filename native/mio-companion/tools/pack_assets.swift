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
    ("arm_left", CGRect(x: 640, y: 140, width: 370, height: 540), [34, 280, 230, 320], "arm_left"),
    ("arm_right", CGRect(x: 1160, y: 140, width: 376, height: 540), [336, 280, 230, 320], "arm_right"),
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
        layer["bendSpans"] = [0, 0]
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
// Register the new complete, continuous sleeve art by shoulder and wrist.
// Sampling is a geometric registration of imagegen pixels, not new painting.
let continuousArms = load("art/live2d/mio/articulated/arms-continuous.png")
let continuousPixels = rgba(continuousArms)
let segmentedArms = load("art/live2d/mio/articulated/arm-segments-20261021.png")
let segmentedPixels = rgba(segmentedArms)
for side in ["left","right"] {
    let i = layers.firstIndex { $0["id"] as? String == "arm_\(side)" }!
    let r = layers[i]["rect"] as! [Double]
    let sourceShoulder = CGPoint(x:side == "left" ? 581 : 955,y:150)
    let sourceWrist = CGPoint(x:side == "left" ? 211 : 1325,y:800)
    let shoulder = CGPoint(x:side == "left" ? 231 : 369,y:320)
    let wrist = CGPoint(x:side == "left" ? 114 : 486,y:508)
    let scale = hypot(wrist.x-shoulder.x,wrist.y-shoulder.y)/hypot(sourceWrist.x-sourceShoulder.x,sourceWrist.y-sourceShoulder.y)
    let angle = atan2(wrist.y-shoulder.y,wrist.x-shoulder.x)-atan2(sourceWrist.y-sourceShoulder.y,sourceWrist.x-sourceShoulder.x)
    let width = Int(r[2]*3), height = Int(r[3]*3)
    var bytes = [UInt8](repeating:0,count:width*height*4)
    for y in 0..<height { for x in 0..<width {
        let dx = r[0]+(Double(x)+0.5)/3-shoulder.x, dy = r[1]+(Double(y)+0.5)/3-shoulder.y
        let sx = sourceShoulder.x+(dx*cos(angle)+dy*sin(angle))/scale
        let sy = sourceShoulder.y+(-dx*sin(angle)+dy*cos(angle))/scale
        let ix = Int(floor(sx)), iy = Int(floor(sy))
        guard ix >= 0,iy >= 0,ix+1 < continuousArms.width,iy+1 < continuousArms.height,
              side == "left" ? sx < 768 : sx >= 768 else { continue }
        let fx = sx-Double(ix), fy = sy-Double(iy)
        for c in 0..<4 {
            let a = Double(continuousPixels[(iy*continuousArms.width+ix)*4+c])
            let b = Double(continuousPixels[(iy*continuousArms.width+ix+1)*4+c])
            let d = Double(continuousPixels[((iy+1)*continuousArms.width+ix)*4+c])
            let e = Double(continuousPixels[((iy+1)*continuousArms.width+ix+1)*4+c])
            bytes[(y*width+x)*4+c] = UInt8(max(0,min(255,(a*(1-fx)+b*fx)*(1-fy)+(d*(1-fx)+e*fx)*fy)))
        }
    } }
    write(makeImage(bytes,width:width,height:height),"arm_\(side)")
    layers[i]["sourceAtlas"] = "articulated/arms-continuous.png"
    layers[i]["sourceShoulder"] = [sourceShoulder.x,sourceShoulder.y]
    layers[i]["sourceWrist"] = [sourceWrist.x,sourceWrist.y]
    layers[i].removeValue(forKey:"sourceCrop")
}
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
    cut("arm_\(side)") { x,y in along(x,y,wrist) < -54 }
    cut("sleeve_\(side)") { x,y in
        return along(x,y,shoulder) >= 16 && along(x,y,wrist) < -54
    }
    let sleeveImage = load("native/mio-companion/Sources/MioApp/Resources/Mio/sleeve_\(side).png")
    var sleeveBytes = rgba(sleeveImage)
    for y in 0..<sleeveImage.height { for x in 0..<sleeveImage.width {
        let px = r[0]+(Double(x)+0.5)/Double(sleeveImage.width)*r[2]
        let py = r[1]+(Double(y)+0.5)/Double(sleeveImage.height)*r[3]
        let fraction = max(0,min(1,(along(px,py,shoulder)-16)/36))
        let opacity = fraction*fraction*(3-2*fraction)
        for c in 0..<4 {
            let i = (y*sleeveImage.width+x)*4+c
            sleeveBytes[i] = UInt8(Double(sleeveBytes[i])*opacity)
        }
    } }
    write(makeImage(sleeveBytes,width:sleeveImage.width,height:sleeveImage.height),"sleeve_\(side)")
    var sleeve = arm; sleeve["id"] = "sleeve_\(side)"; sleeve["texture"] = "sleeve_\(side).png"
    layers.append(sleeve)
    cut("forearm_\(side)") { x,y in along(x,y,wrist) >= -62 && along(x,y,wrist) < 2 }
    var forearm = arm;forearm["id"] = "forearm_\(side)";forearm["texture"] = "forearm_\(side).png"
    layers.append(forearm)
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
    // Register each sheet by its actual thumb/knuckle view. The inward sheet
    // has the opposite anatomical column order from the palm/back/fist sheets.
    func sourceLeft(for variant: String) -> Bool {
        variant == "inward" ? side == "left" : side == "right"
    }
    let variants: [(String,String,CGPoint)] = [
        ("palm","palms-out",CGPoint(x: sourceLeft(for:"palm") ? 425 : 1110,y:500)),
        ("back","hands-back",CGPoint(x: sourceLeft(for:"back") ? 443 : 1092,y:500)),
        ("inward","hands-inward",CGPoint(x: sourceLeft(for:"inward") ? 437 : 1092,y:465)),
        ("fist","fists",CGPoint(x: sourceLeft(for:"fist") ? 426 : 1110,y:565))
    ]
    for (variant, file, pivot) in variants {
        let atlas = load("art/live2d/mio/pose-parts/\(file).png")
        let cropX = sourceLeft(for:variant) ? 150 : 850
        let image = atlas.cropping(to:CGRect(x:cropX,y:40,width:600,height:930))!
        let context = context()
        context.translateBy(x:wrist.x-handRect[0],y:handRect[3]-(wrist.y-handRect[1]))
        context.rotate(by: atan2(d.x,d.y))
        if variant == "fist" {
            // Its longer source forearm remains hidden beneath the same cuff.
            context.clip(to:CGRect(x:-100,y:-150,width:200,height:212))
        }
        let sx: CGFloat = 0.17, sy: CGFloat = 0.16
        context.draw(image,in:CGRect(x:(CGFloat(cropX)-pivot.x)*sx,
            y:(pivot.y-40-CGFloat(image.height))*sy,width:CGFloat(image.width)*sx,height:CGFloat(image.height)*sy))
        write(context.makeImage()!,"hand_\(side)_\(variant)")
    }
    if side == "right" {
        let image = load("art/live2d/mio/pose-parts/chin-index.png").cropping(to:CGRect(x:0,y:0,width:1254,height:1190))!
        let context = context()
        context.translateBy(x:wrist.x-handRect[0],y:handRect[3]-(wrist.y-handRect[1]))
        let angle = atan2(-d.y,-d.x)-atan2(CGFloat(290),CGFloat(74))
        context.rotate(by:-angle)
        // Keep the useful short forearm; the source's distant edge dust is
        // outside this registered cuff coverage and never enters the texture.
        context.clip(to:CGRect(x:-150,y:-90,width:300,height:180))
        // Extend only the bare forearm along its measured source axis. The
        // hand, wrist width and fingertip remain unchanged; this registration
        // deformation puts the source edge under the existing painted cuff.
        let length: CGFloat = sqrt(CGFloat(74*74+290*290))
        let axis = CGVector(dx:74/length,dy:-290/length)
        let normal = CGVector(dx:-axis.dy,dy:axis.dx)
        for forearm in [true,false] {
            context.saveGState()
            let region = CGMutablePath()
            let lo: CGFloat = forearm ? 0 : -250, hi: CGFloat = forearm ? 250 : 0
            let corners = [(lo,CGFloat(-200)),(lo,CGFloat(200)),(hi,CGFloat(200)),(hi,CGFloat(-200))]
            for (index,corner) in corners.enumerated() {
                let p = CGPoint(x:axis.dx*corner.0+normal.dx*corner.1,y:axis.dy*corner.0+normal.dy*corner.1)
                if index == 0 { region.move(to:p) } else { region.addLine(to:p) }
            }
            region.closeSubpath();context.addPath(region);context.clip()
            if forearm {
                let k: CGFloat = 1.4
                context.concatenate(CGAffineTransform(a:1+k*axis.dx*axis.dx,b:k*axis.dx*axis.dy,
                    c:k*axis.dx*axis.dy,d:1+k*axis.dy*axis.dy,tx:0,ty:0))
            }
            context.draw(image,in:CGRect(x:-825*0.09,y:(870-CGFloat(image.height))*0.09,
                                         width:CGFloat(image.width)*0.09,height:CGFloat(image.height)*0.09))
            context.restoreGState()
        }
        write(context.makeImage()!,"hand_right_chin")
        let full = load("native/mio-companion/Sources/MioApp/Resources/Mio/hand_right_chin.png")
        let original = rgba(full)
        for front in [true,false] {
            var pixels = original
            for y in 0..<full.height { for x in 0..<full.width {
                let px = handRect[0]+(Double(x)+0.5)/3, py = handRect[1]+(Double(y)+0.5)/3
                let distance = along(px,py,wrist)
                if front && distance < -20 {
                    let index = (y*full.width+x)*4
                    for channel in 0..<4 { pixels[index+channel] = 0 }
                }
            } }
            write(makeImage(pixels,width:full.width,height:full.height),front ? "hand_right_chin_front" : "hand_right_chin")
        }
        var front = arm
        front["id"] = "hand_right_chin_front";front["texture"] = "hand_right_chin_front.png"
        front["rect"] = handRect;front["group"] = "hand_right";front["jointPiece"] = "forearm"
        front["binding"] = "continuous-elbow-arc";front["defaultVisible"] = false
        front.removeValue(forKey:"jointPiece")
        front["contactPoint"] = [547,554];front["sourceAtlas"] = "pose-parts/chin-index.png"
        layers.append(front)
    }
    for variant in ["relaxed","palm","back","inward","fist"] + (side == "right" ? ["chin"] : []) {
        var hand = arm
        hand["id"] = "hand_\(side)_\(variant)"
        hand["texture"] = "hand_\(side)_\(variant).png"
        hand["group"] = "hand_\(side)"
        hand["rect"] = handRect
        hand["variant"] = variant
        hand["defaultVisible"] = variant == "relaxed"
        let atlasName = variant == "fist" ? "fists" : (variant == "palm" ? "palms-out" : "hands-\(variant)")
        hand["sourceAtlas"] = variant == "relaxed" ? "articulated/arms-continuous.png" : "pose-parts/\(atlasName).png"
        hand["wristRegistration"] = [wrist.x,wrist.y]
        hand["anatomicalHand"] = side == "left" ? "right" : "left"
        if variant != "relaxed" {
            hand["sourceColumn"] = sourceLeft(for:variant) ? "left" : "right"
            hand["sourceCrop"] = [sourceLeft(for:variant) ? 150 : 850,40,600,930]
        }
        if variant == "chin" {
            hand["sourceAtlas"] = "pose-parts/chin-index.png"
            hand.removeValue(forKey:"sourceColumn")
            hand["sourceCrop"] = [0,0,1254,1254]
            hand["sourceWrist"] = [825,870]
            hand["sourceIndexTip"] = [353,148]
            hand["contactPoint"] = [547,554]
            hand["registrationScale"] = 0.09
        }
        layers.append(hand)
    }
    // Independent source upper/lower sleeves. Register authored overlap at
    // the same elbow, with the lower cuff and wrist as separate landmarks.
    let segmentWidth = Int(r[2]*3),segmentHeight = Int(r[3]*3)
    let upperStart = CGPoint(x:side == "left" ? 300:940,y:side == "left" ? 150:160)
    let upperEnd = CGPoint(x:side == "left" ? 220:1020,y:645)
    let upperAxis = CGPoint(x:upperEnd.x-upperStart.x,y:upperEnd.y-upperStart.y)
    let upperLength = hypot(upperAxis.x,upperAxis.y),upperTargetLength = hypot(elbow.x-shoulder.x,elbow.y-shoulder.y)
    let ud = CGPoint(x:upperAxis.x/upperLength,y:upperAxis.y/upperLength)
    let td = CGPoint(x:(elbow.x-shoulder.x)/upperTargetLength,y:(elbow.y-shoulder.y)/upperTargetLength)
    let lowerX: Double = side == "left" ? 590:1240
    func smooth(_ low: Double,_ high: Double,_ value: Double) -> Double {
        let q = max(0,min(1,(value-low)/(high-low)));return q*q*(3-2*q)
    }
    func sample(_ sx: Double,_ sy: Double,_ bounds: ClosedRange<Double>,_ opacity: Double,_ result: inout [UInt8],_ index: Int) {
        let ix = Int(floor(sx)),iy = Int(floor(sy))
        guard ix>=0,iy>=0,ix+1<segmentedArms.width,iy+1<segmentedArms.height,bounds.contains(sx) else { return }
        let fx=sx-Double(ix),fy=sy-Double(iy)
        for c in 0..<4 {
            let a=Double(segmentedPixels[(iy*segmentedArms.width+ix)*4+c]),b=Double(segmentedPixels[(iy*segmentedArms.width+ix+1)*4+c])
            let e=Double(segmentedPixels[((iy+1)*segmentedArms.width+ix)*4+c]),f=Double(segmentedPixels[((iy+1)*segmentedArms.width+ix+1)*4+c])
            result[index+c] = UInt8(max(0,min(255,((a*(1-fx)+b*fx)*(1-fy)+(e*(1-fx)+f*fx)*fy)*opacity)))
        }
    }
    var upperBytes=[UInt8](repeating:0,count:segmentWidth*segmentHeight*4)
    var lowerBytes=upperBytes,skinBytes=upperBytes,frontBytes=upperBytes
    for y in 0..<segmentHeight { for x in 0..<segmentWidth {
        let px=r[0]+(Double(x)+0.5)/3,py=r[1]+(Double(y)+0.5)/3,index=(y*segmentWidth+x)*4
        let ux=(px-shoulder.x)*td.x+(py-shoulder.y)*td.y,uy = -(px-shoulder.x)*td.y+(py-shoulder.y)*td.x
        let su=ux*upperLength/upperTargetLength,sv=uy/(upperTargetLength/upperLength*0.85)
        let sx=upperStart.x+ud.x*su-ud.y*sv,sy=upperStart.y+ud.y*su+ud.x*sv
        // Fade only the hidden attachment edge. The other segment supplies
        // opaque fabric underneath; exterior shoulder and sleeve art remain.
        let upperOpacity=(1-smooth(upperTargetLength+2,upperTargetLength+15,ux))*(1-smooth(19,22,abs(uy)))
        sample(sx,sy,side == "left" ? 100...420:820...1120,upperOpacity,&upperBytes,index)
        let frontOpacity=smooth(16,52,ux)
        for c in 0..<4 { frontBytes[index+c]=UInt8(Double(upperBytes[index+c])*frontOpacity) }
        let lx=(px-elbow.x)*d.x+(py-elbow.y)*d.y,ly = -(px-elbow.x)*d.y+(py-elbow.y)*d.x
        let cuffDistance=length-54
        let sourceY = lx<=cuffDistance ? 260+lx*(650-260)/cuffDistance : 650+(lx-cuffDistance)*(900-650)/54
        let sourceX=lowerX+ly/0.20
        let lowerOpacity=smooth(-18,-6,lx)
        if lx<length-42 { sample(sourceX,sourceY,side == "left" ? 470...710:1125...1350,lowerOpacity,&lowerBytes,index) }
        if lx>=length-50 && lx<length+2 { sample(sourceX,sourceY,side == "left" ? 470...710:1125...1350,1,&skinBytes,index) }
    } }
    write(makeImage(upperBytes,width:segmentWidth,height:segmentHeight),"arm_\(side)")
    write(makeImage(frontBytes,width:segmentWidth,height:segmentHeight),"sleeve_\(side)")
    write(makeImage(lowerBytes,width:segmentWidth,height:segmentHeight),"lower_sleeve_\(side)")
    write(makeImage(skinBytes,width:segmentWidth,height:segmentHeight),"forearm_\(side)")
    for id in ["arm_\(side)","sleeve_\(side)","forearm_\(side)"] {
        let index = layers.firstIndex { $0["id"] as? String == id }!
        layers[index]["jointPiece"] = id.hasPrefix("forearm") ? "forearm":"upper"
        layers[index]["sourceAtlas"] = "articulated/arm-segments-20261021.png"
        layers[index]["binding"] = "anatomical-two-bone-overlap"
    }
    var lower=arm;lower["id"]="lower_sleeve_\(side)";lower["texture"]="lower_sleeve_\(side).png"
    lower["jointPiece"]="forearm";lower["sourceAtlas"]="articulated/arm-segments-20261021.png";lower["binding"]="anatomical-two-bone-overlap"
    layers.append(lower)
    for index in layers.indices where (layers[index]["group"] as? String) == "hand_\(side)" { layers[index]["jointPiece"] = "forearm";layers[index]["binding"] = "anatomical-two-bone-overlap" }
    // Measure the painted wrist contour, then weld every source drawing to
    // the same forearm width/centre. A shared bone alone does not align art.
    let forearmImage = load("native/mio-companion/Sources/MioApp/Resources/Mio/forearm_\(side).png")
    let forearmPixels = rgba(forearmImage)
    func profile(_ image: CGImage,_ pixels: [UInt8],_ rect: [Double]) -> (Double,Double) {
        var values: [Double] = []
        for step in -160...160 {
            let across = Double(step)/4
            let px = wrist.x-d.y*across,py = wrist.y+d.x*across
            let x = Int((px-rect[0])/rect[2]*Double(image.width)),y = Int((py-rect[1])/rect[3]*Double(image.height))
            if x>=0 && y>=0 && x<image.width && y<image.height && pixels[(y*image.width+x)*4+3] >= 128 { values.append(across) }
        }
        precondition(values.count > 12)
        return ((values.first!+values.last!)/2,(values.last!-values.first!)/2)
    }
    let targetProfile = profile(forearmImage,forearmPixels,r)
    // Keep a shared opaque forearm. The selected hand overlaps and feathers
    // into it at the wrist; no duplicated full forearms or straight cut edge.
    for variant in ["relaxed","palm","back","inward","fist","chin","chin_front"] where side == "right" || !variant.hasPrefix("chin") {
        let name = "hand_\(side)_\(variant)"
        let image = load("native/mio-companion/Sources/MioApp/Resources/Mio/\(name).png")
        let original = rgba(image)
        let sourceProfile = profile(image,original,handRect)
        var pixels = [UInt8](repeating:0,count:original.count)
        for y in 0..<image.height { for x in 0..<image.width {
            let px = handRect[0]+(Double(x)+0.5)/3, py = handRect[1]+(Double(y)+0.5)/3
            let position = along(px,py,wrist)
            let across = (px-wrist.x)*(-d.y)+(py-wrist.y)*d.x
            let turn = max(0,min(1,(position-4)/24))
            let influence = 1-turn*turn*(3-2*turn)
            let mapped = (across-targetProfile.0)*sourceProfile.1/targetProfile.1+sourceProfile.0
            let a = across+(mapped-across)*influence
            let sx = (wrist.x+d.x*position-d.y*a-handRect[0])*3-0.5
            let sy = (wrist.y+d.y*position+d.x*a-handRect[1])*3-0.5
            let ix = Int(floor(sx)),iy = Int(floor(sy))
            guard ix>=0,iy>=0,ix+1<image.width,iy+1<image.height else {continue}
            let fx = sx-Double(ix),fy = sy-Double(iy)
            let fraction = max(0,min(1,(position+10)/8))
            let opacity = fraction*fraction*(3-2*fraction)
            for c in 0..<4 {
                let a = Double(original[(iy*image.width+ix)*4+c]),b = Double(original[(iy*image.width+ix+1)*4+c])
                let e = Double(original[((iy+1)*image.width+ix)*4+c]),f = Double(original[((iy+1)*image.width+ix+1)*4+c])
                pixels[(y*image.width+x)*4+c] = UInt8(max(0,min(255,((a*(1-fx)+b*fx)*(1-fy)+(e*(1-fx)+f*fx)*fy)*opacity)))
            }
        } }
        write(makeImage(pixels,width:image.width,height:image.height),name)
        if let index = layers.firstIndex(where: { $0["id"] as? String == name }) {
            layers[index]["wristProfile"] = [targetProfile.0,targetProfile.1]
        }
    }
}
// A simple native vector thought bubble, exported with the source layers.
let cloudWidth = 468, cloudHeight = 285
let cloud = CGContext(data:nil,width:cloudWidth,height:cloudHeight,bitsPerComponent:8,
    bytesPerRow:cloudWidth*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
cloud.scaleBy(x:3,y:3); cloud.translateBy(x:0,y:95); cloud.scaleBy(x:1,y:-1)
cloud.setFillColor(NSColor(calibratedRed:0.99,green:0.99,blue:0.97,alpha:0.97).cgColor)
cloud.setStrokeColor(NSColor(calibratedRed:0.46,green:0.57,blue:0.63,alpha:1).cgColor)
cloud.setLineWidth(1.5)
let bubble = CGMutablePath()
bubble.move(to:CGPoint(x:28,y:58))
bubble.addCurve(to:CGPoint(x:14,y:28),control1:CGPoint(x:4,y:58),control2:CGPoint(x:3,y:36))
bubble.addCurve(to:CGPoint(x:46,y:13),control1:CGPoint(x:11,y:7),control2:CGPoint(x:32,y:2))
bubble.addCurve(to:CGPoint(x:79,y:10),control1:CGPoint(x:52,y:-1),control2:CGPoint(x:71,y:0))
bubble.addCurve(to:CGPoint(x:113,y:17),control1:CGPoint(x:94,y:0),control2:CGPoint(x:111,y:3))
bubble.addCurve(to:CGPoint(x:142,y:41),control1:CGPoint(x:140,y:10),control2:CGPoint(x:156,y:29))
bubble.addCurve(to:CGPoint(x:115,y:65),control1:CGPoint(x:151,y:60),control2:CGPoint(x:130,y:73))
bubble.addCurve(to:CGPoint(x:75,y:66),control1:CGPoint(x:105,y:80),control2:CGPoint(x:83,y:78))
bubble.addCurve(to:CGPoint(x:28,y:58),control1:CGPoint(x:53,y:76),control2:CGPoint(x:33,y:72))
bubble.closeSubpath();cloud.addPath(bubble);cloud.drawPath(using:.fillStroke)
for rect in [CGRect(x:35,y:75,width:12,height:9),CGRect(x:24,y:88,width:6,height:5)] {
    cloud.addEllipse(in:rect);cloud.drawPath(using:.fillStroke)
}
cloud.setFillColor(NSColor(calibratedRed:0.46,green:0.57,blue:0.63,alpha:1).cgColor)
for x in [55,77,99] { cloud.fillEllipse(in:CGRect(x:x,y:35,width:6,height:6)) }
write(cloud.makeImage()!,"thought_cloud")
layers.append(["id":"thought_cloud","texture":"thought_cloud.png","rect":[365,12,156,95],
               "group":"thought_cloud","defaultVisible":false,"source":"native-vector-path"])
let order = ["hair_back", "lower_body", "shoulder_left", "shoulder_right", "arm_left", "arm_right", "torso",
             "sleeve_left", "sleeve_right", "lower_sleeve_left", "lower_sleeve_right", "forearm_left", "forearm_right",
             "hand_left_relaxed", "hand_left_palm", "hand_left_back", "hand_left_inward", "hand_left_fist",
             "hand_right_relaxed", "hand_right_palm", "hand_right_back", "hand_right_inward", "hand_right_fist", "hand_right_chin",
             "face", "eyes_open", "eyes_closed", "mouth_closed", "mouth_open", "hair_front", "hand_right_chin_front", "thought_cloud"]
layers.sort { order.firstIndex(of: $0["id"] as! String)! < order.firstIndex(of: $1["id"] as! String)! }
let manifest: [String: Any] = ["format": "harumachi-layer-rig", "version": 1, "name": "澪", "canvas": [750, 1000],
                              "origin": [-75, 0],
                              "layoutRevision": "20261021-articulated-v11",
                              "cubismCompatible": false, "layers": layers,
                              "parameters": ["ParamAngleX", "ParamAngleY", "ParamBodyAngleZ", "ParamBreath", "ParamEyeLOpen", "ParamEyeROpen", "ParamMouthOpenY"]]
let json = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
try json.write(to: out.appendingPathComponent("Mio.rig.json"))
try json.write(to: root.appendingPathComponent("art/live2d/mio/Mio.rig.json"))
